import Foundation
import IOKit.pwr_mgt

struct CopyRequest: Sendable {
    let sourceRoot: URL
    let destinationRoot: URL
    let volumeUUID: String
    let sessionID: UUID
    let folders: [MediaFolder]
    var applyFinderTag: Bool = true
    var preventSleep: Bool = true
}

struct CopyProgress: Sendable {
    var totalBytes: Int64 = 0
    var processedBytes: Int64 = 0
    var transferredBytes: Int64 = 0
    var verifiedBytes: Int64 = 0
    var currentFile: String = "Preparazione…"
    var currentFileBytes: Int64 = 0
    var currentFileSize: Int64 = 0
    var totalFiles: Int = 0
    var fileCount: Int = 0
    var skippedCount: Int = 0
    var failedCount: Int = 0
    var bytesPerSecond: Double = 0
    var fraction: Double { totalBytes > 0 ? min(1, Double(processedBytes) / Double(totalBytes)) : 0 }
}

enum CopyEvent: Sendable {
    case progress(CopyProgress)
    case verified(LedgerEntry)
}

struct CopyOutcome: Sendable {
    var status: CardStatus = .completata
    var fileCount = 0
    var copiedBytes: Int64 = 0
    var skippedCount = 0
    var errors: [String] = []
    var entries: [LedgerEntry] = []
}

actor CopyEngine {
    typealias SizeReader = @Sendable (URL) throws -> Int64
    private let destinationSize: SizeReader
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    init(destinationSize: @escaping SizeReader = { url in
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs[.size] as? NSNumber)?.int64Value ?? -1
    }) { self.destinationSize = destinationSize }

    private func acquire() async {
        if !busy { busy = true; return }
        await withCheckedContinuation { waiters.append($0) }
    }
    private func release() {
        if waiters.isEmpty { busy = false } else { waiters.removeFirst().resume() }
    }

    /// A single actor-owned FIFO gate also prevents reentrant runs during events.
    func run(_ request: CopyRequest, ledgerEntries: [LedgerEntry], event: @escaping @Sendable (CopyEvent) async -> Void) async -> CopyOutcome {
        await acquire()
        defer { release() }
        var outcome = CopyOutcome()
        var ledger = Ledger(entries: ledgerEntries)
        let files = request.folders.flatMap(\.files).sorted { $0.relativePath < $1.relativePath }
        var progress = CopyProgress(totalBytes: files.reduce(0) { $0 + $1.size }, totalFiles: files.count)
        let start = Date()
        var lastEmission = Date.distantPast
        var assertion: IOPMAssertionID = 0
        let asserted = request.preventSleep && IOPMAssertionCreateWithName(kIOPMAssertPreventUserIdleSystemSleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "M — scaricamento scheda" as CFString, &assertion) == kIOReturnSuccess
        defer { if asserted { IOPMAssertionRelease(assertion) } }
        do {
            try Task.checkCancellation()
            try validateRoots(request)
            try FileManager.default.createDirectory(at: request.destinationRoot, withIntermediateDirectories: true)
            for directory in Set(request.folders.flatMap(\.directories)).sorted() {
                try Task.checkCancellation()
                let target = try safeURL(directory, in: request.destinationRoot)
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            }
            for file in files {
                try Task.checkCancellation()
                progress.currentFile = file.relativePath
                progress.currentFileBytes = 0
                progress.currentFileSize = file.size
                lastEmission = .distantPast // First chunk of every file is observable and cancellable.
                if ledger.contains(volumeUUID: request.volumeUUID, file: file) {
                    outcome.skippedCount += 1
                    progress.skippedCount += 1
                    progress.processedBytes += file.size
                    await event(.progress(progress))
                    continue
                }
                let source = try safeURL(file.relativePath, in: request.sourceRoot)
                let target = try safeURL(file.relativePath, in: request.destinationRoot)
                let staging = target.deletingLastPathComponent().appendingPathComponent(".M-\(UUID().uuidString).partial")
                let processedBefore = progress.processedBytes
                do {
                    try checkSource(source, matches: file)
                    try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                    guard !FileManager.default.fileExists(atPath: target.path) else {
                        throw IngestError.message("Il file di destinazione esiste già; non è stato sovrascritto.")
                    }
                    if let link = file.symbolicLinkTarget {
                        try validateSymbolicLink(link, at: source, root: request.sourceRoot)
                        try FileManager.default.createSymbolicLink(atPath: staging.path, withDestinationPath: link)
                        progress.transferredBytes += file.size
                        progress.currentFileBytes = file.size
                        progress.processedBytes += file.size
                    } else {
                    guard let input = InputStream(url: source), let output = OutputStream(url: staging, append: false) else {
                        throw IngestError.message("Impossibile aprire i flussi del file.")
                    }
                    input.open(); output.open()
                    do {
                        defer { input.close(); output.close() }
                        var buffer = [UInt8](repeating: 0, count: 1_048_576)
                        while true {
                            try Task.checkCancellation()
                            let count = input.read(&buffer, maxLength: buffer.count)
                            if count < 0 { throw input.streamError ?? IngestError.message("Errore di lettura.") }
                            if count == 0 { break }
                            var offset = 0
                            while offset < count {
                                try Task.checkCancellation()
                                let written = buffer.withUnsafeBufferPointer { ptr in
                                    output.write(ptr.baseAddress!.advanced(by: offset), maxLength: count - offset)
                                }
                                guard written > 0 else { throw output.streamError ?? IngestError.message("Scrittura interrotta o spazio esaurito.") }
                                offset += written
                                progress.transferredBytes += Int64(written)
                                progress.currentFileBytes += Int64(written)
                                progress.processedBytes += Int64(written)
                            }
                            if Date().timeIntervalSince(lastEmission) >= 0.08 {
                                progress.bytesPerSecond = Double(progress.transferredBytes) / max(0.001, Date().timeIntervalSince(start))
                                await event(.progress(progress))
                                lastEmission = Date()
                            }
                        }
                        if let error = output.streamError { throw error }
                    }
                    }
                    try Task.checkCancellation()
                    try checkSource(source, matches: file)
                    guard try destinationSize(staging) == file.size else {
                        throw IngestError.message("Verifica dimensione non riuscita: sorgente e destinazione non coincidono.")
                    }
                    if file.symbolicLinkTarget == nil { try FileManager.default.setAttributes([.modificationDate: file.modified], ofItemAtPath: staging.path) }
                    try FileManager.default.moveItem(at: staging, to: target)
                    let entry = LedgerEntry(volumeUUID: request.volumeUUID, relativePath: file.relativePath, size: file.size, sourceModified: file.modified, sessionID: request.sessionID, copiedAt: Date())
                    ledger.insert(entry)
                    outcome.entries.append(entry)
                    outcome.fileCount += 1
                    outcome.copiedBytes += file.size
                    progress.fileCount = outcome.fileCount
                    progress.verifiedBytes = outcome.copiedBytes
                    if request.applyFinderTag && file.symbolicLinkTarget == nil {
                        var taggedSource = source
                        var values = URLResourceValues()
                        values.labelNumber = 6 // Finder's red label (URLResourceValues has no .label/.red API).
                        try? taggedSource.setResourceValues(values)
                    }
                    await event(.verified(entry))
                } catch is CancellationError {
                    try? FileManager.default.removeItem(at: staging)
                    throw CancellationError()
                } catch {
                    try? FileManager.default.removeItem(at: staging)
                    outcome.errors.append("\(file.relativePath): \(error.localizedDescription)")
                    progress.failedCount += 1
                    progress.processedBytes = processedBefore + file.size
                }
                progress.bytesPerSecond = Double(progress.transferredBytes) / max(0.001, Date().timeIntervalSince(start))
                await event(.progress(progress))
            }
            try Task.checkCancellation()
            if !outcome.errors.isEmpty { outcome.status = outcome.fileCount > 0 || outcome.skippedCount > 0 ? .parziale : .fallita }
        } catch is CancellationError {
            outcome.status = .parziale
            outcome.errors.append("Scaricamento annullato. I file già verificati restano disponibili; il file incompleto è stato rimosso.")
        } catch {
            outcome.status = .fallita
            outcome.errors.append(error.localizedDescription)
        }
        await event(.progress(progress))
        return outcome
    }

    private func validateRoots(_ request: CopyRequest) throws {
        let source = request.sourceRoot.resolvingSymlinksInPath().standardizedFileURL.path
        let destination = request.destinationRoot.resolvingSymlinksInPath().standardizedFileURL.path
        guard source != destination, !destination.hasPrefix(source + "/") else {
            throw IngestError.message("La destinazione non può trovarsi sulla scheda sorgente.")
        }
    }
    /// A card symlink is recreated at destination only when its target resolves
    /// INSIDE the card (QA Finding 1): escaping links must never be planted in the
    /// user's photo library, where sync/backup/index tools would follow them.
    /// Absolute targets and relative `..` chains are both contained-checked after
    /// resolution; a rejected link surfaces as a per-file error, like size mismatches.
    private func validateSymbolicLink(_ link: String, at source: URL, root: URL) throws {
        let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
        let linkDirectory = source.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
        let candidate = (link as NSString).isAbsolutePath
            ? URL(fileURLWithPath: link)
            : linkDirectory.appendingPathComponent(link)
        let resolved = candidate.resolvingSymlinksInPath().standardizedFileURL.path
        guard resolved == rootPath || resolved.hasPrefix(rootPath + "/") else {
            throw IngestError.message("Il collegamento rimanda a un percorso fuori dalla scheda; non è stato creato.")
        }
    }
    private func safeURL(_ relative: String, in root: URL) throws -> URL {
        let components = relative.split(separator: "/", omittingEmptySubsequences: false)
        guard !relative.isEmpty, !relative.hasPrefix("/"), components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw IngestError.message("Percorso relativo non valido.")
        }
        let base = root.resolvingSymlinksInPath().standardizedFileURL
        let literal = base.appendingPathComponent(relative)
        let parent = literal.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
        guard parent.path == base.path || parent.path.hasPrefix(base.path + "/") else { throw IngestError.message("Collegamento esterno alla cartella consentita.") }
        return parent.appendingPathComponent(literal.lastPathComponent)
    }
    private func checkSource(_ url: URL, matches file: ScannedFile) throws {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let expectedType: FileAttributeType = file.symbolicLinkTarget == nil ? .typeRegular : .typeSymbolicLink
        guard attrs[.type] as? FileAttributeType == expectedType, (attrs[.size] as? NSNumber)?.int64Value == file.size, attrs[.modificationDate] as? Date == file.modified else {
            throw IngestError.message("La sorgente è cambiata dopo la scansione. Esegui una nuova scansione.")
        }
        if let target = file.symbolicLinkTarget, try FileManager.default.destinationOfSymbolicLink(atPath: url.path) != target {
            throw IngestError.message("Il collegamento sorgente è cambiato dopo la scansione.")
        }
    }
}
