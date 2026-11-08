import Foundation
import Testing
@testable import M

@MainActor
struct AppModelTests {
    @Test func noActiveSessionNeverCopiesAndLedgerSurvivesAcrossSessions() async throws {
        let f = try Fixture()
        let sourceFile = try f.put("source/DCIM/a.JPG")
        let source = f.root.appendingPathComponent("source")
        let destination = f.root.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let repository = StoreRepository(url: f.root.appendingPathComponent("support/store.json"))
        var model = AppModel(repository: repository, systemEffects: false)
        let volume = MountedCard(url: source, name: "SD", volumeUUID: "fixture-uuid")
        model.didMount(volume) // Synthetic event: never starts CardWatcher or NSWorkspace.
        await model.waitForScan(volume.id)
        model.startCopy(volume.id)
        #expect(model.store.cards.isEmpty)
        #expect(model.errorText?.contains("Nessuna sessione attiva") == true)
        model.errorText = nil
        model.createSession(name: "Prima", destination: destination)
        let firstSession = try #require(model.activeSession)
        model.startCopy(volume.id)
        // A selection change must never retarget a running request.
        model.createSession(name: "Seconda", destination: destination)
        await model.waitForCurrentCopy()
        #expect(model.store.cards.first?.sessionID == firstSession.id)
        #expect(model.store.cards.first?.status == .completata)
        model.didUnmount(volume)
        model = AppModel(repository: repository, systemEffects: false) // Real JSON reload, not an in-memory ledger.
        model.didMount(volume)
        await model.waitForScan(volume.id)
        model.startCopy(volume.id)
        await model.waitForCurrentCopy()
        #expect(model.store.cards.last?.status == .completata)
        #expect(model.store.cards.last?.skippedCount == 1)
        #expect(model.store.cards.last?.fileCount == 0)
        #expect(model.store.cards.last?.folderName == "SD")
        // RECALCULATED per V1 ruling: cards now live in per-session folders, so the
        // old cross-session "SD 2" collision cannot happen; the layout pin replaces it.
        let firstCardDest = try #require(model.store.cards.first?.destPath)
        let lastCardDest = try #require(model.store.cards.last?.destPath)
        #expect(firstCardDest.hasPrefix(destination.appendingPathComponent("Prima").path + "/"))
        #expect(lastCardDest.hasPrefix(destination.appendingPathComponent("Seconda").path + "/"))
        #expect(try Data(contentsOf: sourceFile) == Data("fixture".utf8))
        #expect(try repository.load().store.ledger.count == 1)
        #expect(model.store.sessions.allSatisfy { $0.cardIDs.count == 1 })
    }

    @Test func sessionFolderIsCreatedInsideDestinationAndReused() async throws {
        // V1 ruling: <container>/<session>/ holds the cards and the report.
        let f = try Fixture()
        try f.put("source/DCIM/a.JPG")
        let container = f.root.appendingPathComponent("container")
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        let repository = StoreRepository(url: f.root.appendingPathComponent("support/store.json"))
        var model = AppModel(repository: repository, systemEffects: false)
        model.createSession(name: "Matrimonio", destination: container)
        model.createSession(name: "Matrimonio", destination: container)
        #expect(model.errorText == nil)
        // Same name twice: session folders are unique like card folders.
        #expect(model.store.sessions.map { $0.folderURL.lastPathComponent } == ["Matrimonio 2", "Matrimonio"])
        #expect(FileManager.default.fileExists(atPath: container.appendingPathComponent("Matrimonio", isDirectory: true).path))
        let volume = MountedCard(url: f.root.appendingPathComponent("source"), name: "SD", volumeUUID: "fixture-uuid")
        model.didMount(volume)
        await model.waitForScan(volume.id)
        model.startCopy(volume.id)
        await model.waitForCurrentCopy()
        let session = try #require(model.activeSession)
        #expect(model.store.cards.first?.destPath == container.appendingPathComponent("Matrimonio 2/SD").path)
        let report = try ReportWriter.write(session: session, cards: model.cards(for: session))
        #expect(report.deletingLastPathComponent().path == container.appendingPathComponent("Matrimonio 2").path)
        // A same-named FILE blocks the session folder without touching that file.
        let blocker = container.appendingPathComponent("Bloccata")
        try Data("importante".utf8).write(to: blocker)
        model.createSession(name: "Bloccata", destination: container)
        #expect(model.activeSession?.name == "Bloccata") // reserve() routed around the file: «Bloccata 2».
        #expect(model.activeSession?.folderURL.lastPathComponent == "Bloccata 2")
        #expect(try Data(contentsOf: blocker) == Data("importante".utf8))
    }

    @Test func legacySessionWithoutFolderPathAdoptsDerivedFolderOnNextCopy() async throws {
        // V1 ruling point 4: stores saved before the ruling adopt <container>/<name>/.
        let f = try Fixture()
        try f.put("source/DCIM/a.JPG")
        let container = f.root.appendingPathComponent("container")
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        let repository = StoreRepository(url: f.root.appendingPathComponent("support/store.json"))
        let legacy = SessionRecord(name: "Vecchia", destinationPath: container.path) // folderPath nil
        try repository.save(Store(sessions: [legacy]))
        var model = AppModel(repository: repository, systemEffects: false)
        let volume = MountedCard(url: f.root.appendingPathComponent("source"), name: "SD", volumeUUID: "fixture-uuid")
        model.didMount(volume)
        await model.waitForScan(volume.id)
        model.startCopy(volume.id)
        await model.waitForCurrentCopy()
        #expect(model.store.cards.first?.destPath == container.appendingPathComponent("Vecchia/SD").path)
        #expect(try repository.load().store.sessions.first?.folderPath == container.appendingPathComponent("Vecchia").path)
    }

    @Test func syntheticUnmountAndRemountMarksRunningCardFailedWithoutCorruptingNewDraft() async throws {
        let f = try Fixture()
        try f.put("source/a.JPG")
        let destination = f.root.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let repository = StoreRepository(url: f.root.appendingPathComponent("support/store.json"))
        let model = AppModel(repository: repository, systemEffects: false)
        model.createSession(name: "Test", destination: destination)
        let volume = MountedCard(url: f.root.appendingPathComponent("source"), name: "SD", volumeUUID: "fixture-uuid")
        model.didMount(volume)
        await model.waitForScan(volume.id)
        let oldToken = try #require(model.drafts.first?.token)
        model.startCopy(volume.id)
        #expect(model.isCopying)
        model.didUnmount(volume)
        model.didMount(volume)
        await model.waitForCurrentCopy()
        await model.waitForScan(volume.id)
        #expect(model.store.cards.first?.status == .fallita)
        #expect(model.store.cards.first?.errors.contains { $0.contains("rimossa o rimontata") } == true)
        #expect(model.drafts.first?.token != oldToken)
        #expect(model.drafts.first?.phase == .ready)
        #expect(try repository.load().store.cards.first?.status == .fallita)
    }

    @Test func interruptedRecordIsRecoveredAsPartialOnNextLaunch() throws {
        let f = try Fixture()
        let repository = StoreRepository(url: f.root.appendingPathComponent("store.json"))
        let session = SessionRecord(name: "Test", destinationPath: f.root.path)
        let card = CardRecord(sessionID: session.id, volumeName: "SD", volumeUUID: "A", folderName: "SD", destPath: f.root.path)
        try repository.save(Store(sessions: [session], cards: [card]))
        let model = AppModel(repository: repository, systemEffects: false)
        #expect(model.store.cards.first?.status == .parziale)
        #expect(model.store.cards.first?.finishedAt != nil)
        #expect(try repository.load().store.cards.first?.status == .parziale)
    }
}
