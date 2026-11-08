import AppKit
import Combine
import Foundation

struct CardDraft: Identifiable {
    enum Phase { case scanning, ready, copying, finished, failed }
    var id: String { volume.id }
    let token = UUID()
    let volume: MountedCard
    var phase: Phase = .scanning
    var scan: ScanResult?
    var selected: Set<String> = []
    var folderName: String
    var message: String?
    var recordID: UUID?
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var store = Store()
    @Published var selectedSessionID: UUID?
    @Published var drafts: [CardDraft] = []
    @Published private(set) var progress = CopyProgress()
    @Published private(set) var activeCopyID: UUID?
    @Published var errorText: String?
    @Published var notice: String?
    @Published private(set) var mounted: [String: MountedCard] = [:]
    private var ledgerIndex = Ledger(entries: [])

    private let repository: StoreRepository
    private let systemEffects: Bool
    private let engine = CopyEngine()
    private let watcher = CardWatcher()
    private var started = false
    private var copyTask: Task<Void, Never>?
    private var scanTasks: [String: Task<Void, Never>] = [:]
    private var checkpoint: Timer?
    private var forcedFailures: [UUID: String] = [:]
    private var persistenceFailed = false

    init(repository: StoreRepository = .standard, systemEffects: Bool = true) {
        self.repository = repository
        self.systemEffects = systemEffects
        do {
            let loaded = try repository.load()
            store = loaded.store
            ledgerIndex = Ledger(entries: store.ledger)
            notice = loaded.warning
            var interrupted = false
            for index in store.cards.indices where store.cards[index].status == .inCorso {
                store.cards[index].status = .parziale
                store.cards[index].finishedAt = Date()
                store.cards[index].errors.append("L’app si è chiusa durante lo scaricamento. Reinserisci la scheda per copiare i file non ancora registrati.")
                interrupted = true
            }
            if interrupted { try repository.save(store) }
            selectedSessionID = store.sessions.first?.id
        } catch {
            // A read/permission error must not silently replace an existing ledger.
            persistenceFailed = true
            errorText = "Registro non accessibile: \(error.localizedDescription). Riavvia M dopo aver ripristinato i permessi."
        }
    }
    var activeSession: SessionRecord? { store.sessions.first { $0.id == selectedSessionID } }
    var isCopying: Bool { activeCopyID != nil }
    func cards(for session: SessionRecord) -> [CardRecord] { store.cards.filter { $0.sessionID == session.id }.sorted { $0.startedAt > $1.startedAt } }
    func card(_ id: UUID?) -> CardRecord? { store.cards.first { $0.id == id } }
    func volume(for card: CardRecord) -> MountedCard? { mounted.values.first { $0.volumeUUID == card.volumeUUID } }
    func alreadyCopied(_ file: ScannedFile, volume: MountedCard) -> Bool { ledgerIndex.contains(volumeUUID: volume.volumeUUID, file: file) }
    func skipped(in folder: MediaFolder, volume: MountedCard) -> Int {
        folder.files.filter { ledgerIndex.contains(volumeUUID: volume.volumeUUID, file: $0) }.count
    }
    func start() {
        guard !started else { return }
        started = true
        watcher.onMount = { [weak self] in self?.didMount($0) }
        watcher.onUnmount = { [weak self] in self?.didUnmount($0) }
        watcher.start()
    }
    func createSession(name: String, destination: URL) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { errorText = "Dai un nome alla sessione."; return }
        guard !persistenceFailed else { errorText = "Il registro non è disponibile. Riavvia M dopo aver ripristinato i permessi."; return }
        do {
            try DestinationCheck.validate(destination, requiredBytes: 0)
            let session = SessionRecord(name: String(trimmed.prefix(120)), destinationPath: destination.path)
            store.sessions.insert(session, at: 0)
            selectedSessionID = session.id
            persist()
        } catch { errorText = error.localizedDescription }
    }
    func didMount(_ volume: MountedCard) {
        mounted[volume.id] = volume
        scanTasks[volume.id]?.cancel()
        drafts.removeAll { $0.id == volume.id }
        let draft = CardDraft(volume: volume, folderName: volume.name)
        drafts.append(draft)
        scan(volume, token: draft.token)
    }
    private func scan(_ volume: MountedCard, token: UUID) {
        scanTasks[volume.id] = Task { [weak self] in
            let worker = Task.detached(priority: .userInitiated) { try ScanEngine.scan(root: volume.url) }
            do {
                let result = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                guard !Task.isCancelled, let self, let index = self.drafts.firstIndex(where: { $0.id == volume.id && $0.token == token }) else { return }
                self.drafts[index].scan = result
                self.drafts[index].selected = Set(result.folders.map(\.id))
                self.drafts[index].phase = .ready
                self.scanTasks.removeValue(forKey: volume.id)
            } catch {
                guard !Task.isCancelled, let self, let index = self.drafts.firstIndex(where: { $0.id == volume.id && $0.token == token }) else { return }
                self.drafts[index].phase = .failed
                self.drafts[index].message = "Scansione non riuscita: \(error.localizedDescription)"
                self.scanTasks.removeValue(forKey: volume.id)
            }
        }
    }
    func rescan(_ id: String) {
        guard let index = drafts.firstIndex(where: { $0.id == id }), drafts[index].phase != .copying else { return }
        let volume = drafts[index].volume
        didMount(volume)
    }
    func didUnmount(_ volume: MountedCard) {
        mounted.removeValue(forKey: volume.id)
        scanTasks.removeValue(forKey: volume.id)?.cancel()
        if let id = activeCopyID, let record = card(id), record.volumeUUID == volume.volumeUUID {
            let reason = "La scheda è stata rimossa o rimontata durante la copia. Scaricamento interrotto: reinserisci la scheda e riprova."
            forcedFailures[id] = reason
            if let index = store.cards.firstIndex(where: { $0.id == id }) {
                store.cards[index].status = .fallita
                store.cards[index].errors.append(reason)
                store.cards[index].finishedAt = Date()
            }
            copyTask?.cancel()
            errorText = reason
            persist()
        }
        drafts.removeAll { $0.id == volume.id }
    }
    func startCopy(_ draftID: String) {
        guard !isCopying else { errorText = "Attendi la fine dello scaricamento in corso."; return }
        guard !persistenceFailed else { errorText = "Il registro non è scrivibile. Nessun file verrà copiato."; return }
        guard let session = activeSession else { errorText = "Nessuna sessione attiva. Crea o seleziona una sessione."; return }
        guard let index = drafts.firstIndex(where: { $0.id == draftID }), let scan = drafts[index].scan, mounted[draftID] != nil else { return }
        let draft = drafts[index]
        let folders = scan.folders.filter { draft.selected.contains($0.id) }
        guard !folders.isEmpty else { errorText = "Seleziona almeno una cartella da scaricare."; return }
        do {
            let parent = URL(fileURLWithPath: session.destinationPath, isDirectory: true)
            let source = draft.volume.url.resolvingSymlinksInPath().standardizedFileURL.path
            let destination = parent.resolvingSymlinksInPath().standardizedFileURL.path
            guard source != destination, !destination.hasPrefix(source + "/") else { throw IngestError.message("Scegli una destinazione diversa dalla scheda sorgente.") }
            let ledger = Ledger(entries: store.ledger)
            let newBytes = folders.flatMap(\.files).filter { !ledger.contains(volumeUUID: draft.volume.volumeUUID, file: $0) }.reduce(Int64(0)) { $0 + $1.size }
            try DestinationCheck.validate(parent, requiredBytes: newBytes)
            let name = FolderNaming.sanitize(draft.folderName, volumeName: draft.volume.name)
            let target = try FolderNaming.reserve(in: parent, name: name)
            let record = CardRecord(sessionID: session.id, volumeName: draft.volume.name, volumeUUID: draft.volume.volumeUUID, folderName: target.lastPathComponent, destPath: target.path)
            store.cards.append(record)
            if let sessionIndex = store.sessions.firstIndex(where: { $0.id == session.id }) { store.sessions[sessionIndex].cardIDs.append(record.id) }
            drafts[index].recordID = record.id
            drafts[index].phase = .copying
            activeCopyID = record.id
            progress = CopyProgress(totalBytes: folders.reduce(0) { $0 + $1.byteCount }, totalFiles: folders.flatMap(\.files).count)
            persist()
            guard !persistenceFailed else {
                finish(recordID: record.id, draftID: draft.id, token: draft.token, outcome: CopyOutcome(status: .fallita, errors: ["Registro non scrivibile. Copia non avviata."]))
                return
            }
            checkpoint = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.persist() }
            }
            let request = CopyRequest(sourceRoot: draft.volume.url, destinationRoot: target, volumeUUID: draft.volume.volumeUUID, sessionID: session.id, folders: folders, applyFinderTag: systemEffects, preventSleep: systemEffects)
            let entries = store.ledger
            copyTask = Task { [weak self, engine] in
                let outcome = await engine.run(request, ledgerEntries: entries) { [weak self] event in
                    await self?.receive(event, recordID: record.id)
                }
                self?.finish(recordID: record.id, draftID: draft.id, token: draft.token, outcome: outcome)
            }
        } catch { errorText = error.localizedDescription }
    }
    private func receive(_ event: CopyEvent, recordID: UUID) {
        guard activeCopyID == recordID else { return }
        switch event {
        case .verified(let entry):
            store.ledger.append(entry)
            ledgerIndex.insert(entry)
        case .progress(let value):
            progress = value
            if let index = store.cards.firstIndex(where: { $0.id == recordID }) {
                store.cards[index].fileCount = value.fileCount
                store.cards[index].copiedBytes = value.verifiedBytes
                store.cards[index].skippedCount = value.skippedCount
            }
        }
    }
    private func finish(recordID: UUID, draftID: String, token: UUID, outcome: CopyOutcome) {
        checkpoint?.invalidate(); checkpoint = nil
        if let index = store.cards.firstIndex(where: { $0.id == recordID }) {
            store.cards[index].status = forcedFailures[recordID] == nil ? outcome.status : .fallita
            store.cards[index].fileCount = outcome.fileCount
            store.cards[index].copiedBytes = outcome.copiedBytes
            store.cards[index].skippedCount = outcome.skippedCount
            store.cards[index].finishedAt = Date()
            store.cards[index].errors.append(contentsOf: outcome.errors)
            if let reason = forcedFailures[recordID], !store.cards[index].errors.contains(reason) { store.cards[index].errors.append(reason) }
        }
        if let index = drafts.firstIndex(where: { $0.id == draftID && $0.token == token }) { drafts[index].phase = .finished }
        forcedFailures.removeValue(forKey: recordID)
        activeCopyID = nil
        copyTask = nil
        persist()
    }
    func cancelCopy() { copyTask?.cancel() }
    func waitForCurrentCopy() async { await copyTask?.value }
    func waitForScan(_ id: String) async { await scanTasks[id]?.value }
    func eject(_ volume: MountedCard) {
        guard !isCopying || card(activeCopyID)?.volumeUUID != volume.volumeUUID else { errorText = "Annulla lo scaricamento prima di espellere la scheda."; return }
        do { try NSWorkspace.shared.unmountAndEjectDevice(at: volume.url) }
        catch { errorText = "Espulsione non riuscita: \(error.localizedDescription)" }
    }
    func reveal(_ path: String) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
    func report(_ session: SessionRecord) {
        do {
            let url = try ReportWriter.write(session: session, cards: cards(for: session))
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch { errorText = "Report non creato: \(error.localizedDescription)" }
    }
    private func persist() {
        guard !persistenceFailed else { return }
        do { try repository.save(store) }
        catch {
            persistenceFailed = true
            errorText = "Salvataggio del registro non riuscito: \(error.localizedDescription). Lo scaricamento è stato fermato per proteggere il registro."
            if let id = activeCopyID { forcedFailures[id] = "Registro non salvato: \(error.localizedDescription)" }
            copyTask?.cancel()
        }
    }
}
