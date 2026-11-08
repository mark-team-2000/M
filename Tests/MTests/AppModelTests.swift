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
        #expect(model.store.cards.last?.folderName == "SD 2")
        #expect(try Data(contentsOf: sourceFile) == Data("fixture".utf8))
        #expect(try repository.load().store.ledger.count == 1)
        #expect(model.store.sessions.allSatisfy { $0.cardIDs.count == 1 })
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
