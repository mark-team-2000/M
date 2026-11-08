import Foundation
import Testing
@testable import M

@MainActor
struct ArchiveTests {
    @Test func defaultSessionNameUsesMonthDayTwoDigitYear() {
        var components = DateComponents()
        components.year = 2026; components.month = 11; components.day = 8
        let date = Calendar(identifier: .gregorian).date(from: components)!
        #expect(NewSessionView.defaultSessionName(date: date) == "11.08.26")
        components.month = 3; components.day = 5
        #expect(NewSessionView.defaultSessionName(date: Calendar(identifier: .gregorian).date(from: components)!) == "03.05.26")
    }

    @Test func endSessionWritesReportThenArchivesAndBlocksCopies() async throws {
        let f = try Fixture()
        try f.put("source/DCIM/a.JPG")
        let container = f.root.appendingPathComponent("container")
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        let repository = StoreRepository(url: f.root.appendingPathComponent("support/store.json"))
        var model = AppModel(repository: repository, systemEffects: false)
        model.createSession(name: "Servizio", destination: container)
        let session = try #require(model.activeSession)
        model.endSession(session)
        // Report pasted into the session folder, session archived, selection moved away.
        #expect(model.errorText == nil)
        let report = container.appendingPathComponent("Servizio/REPORT-Servizio.md")
        #expect(FileManager.default.fileExists(atPath: report.path))
        #expect(model.activeSession == nil)
        #expect(try repository.load().store.sessions.first?.isArchived == true)
        // An archived session, even if selected, never receives cards.
        model.selectedSessionID = session.id
        let volume = MountedCard(url: f.root.appendingPathComponent("source"), name: "SD", volumeUUID: "fixture-uuid")
        model.didMount(volume)
        await model.waitForScan(volume.id)
        model.startCopy(volume.id)
        #expect(model.store.cards.isEmpty)
        #expect(model.errorText?.contains("in archivio") == true)
        // Restore brings it back as active.
        model.restoreSession(session)
        #expect(model.selectedSessionID == session.id)
        model.errorText = nil
        model.startCopy(volume.id)
        await model.waitForCurrentCopy()
        #expect(model.store.cards.last?.status == .completata)
    }

    @Test func deleteSessionRemovesRecordsButNeverDiskFiles() throws {
        let f = try Fixture()
        let container = f.root.appendingPathComponent("container")
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        let repository = StoreRepository(url: f.root.appendingPathComponent("support/store.json"))
        var model = AppModel(repository: repository, systemEffects: false)
        model.createSession(name: "Archivio 2025", destination: container)
        let session = try #require(model.activeSession)
        // Simulate delivered photo files inside the session folder.
        let photoDir = container.appendingPathComponent("Archivio 2025/Giorno1/DCIM", isDirectory: true)
        try FileManager.default.createDirectory(at: photoDir, withIntermediateDirectories: true)
        let photo = photoDir.appendingPathComponent("IMG_0001.JPG")
        try Data("precious".utf8).write(to: photo)
        model.createSession(name: "Altra", destination: container)
        let other = try #require(model.activeSession)
        model.deleteSession(session)
        #expect(model.store.sessions.map(\.name) == ["Altra"])
        #expect(model.store.cards.filter { $0.sessionID == session.id }.isEmpty)
        // Disk data survives; selection falls back to a remaining session.
        #expect(try Data(contentsOf: photo) == Data("precious".utf8))
        #expect(model.selectedSessionID == other.id)
        #expect(try repository.load().store.sessions.map(\.name) == ["Altra"])
    }

    @Test func removableCardsAlwaysListBeforeGenericExternalDisks() async throws {
        let f = try Fixture()
        try f.put("disk/DCIM/x.JPG")
        try f.put("card/DCIM/y.JPG")
        let repository = StoreRepository(url: f.root.appendingPathComponent("support/store.json"))
        let model = AppModel(repository: repository, systemEffects: false)
        let generic = MountedCard(url: f.root.appendingPathComponent("disk"), name: "SSD-DEST", volumeUUID: "generic-uuid", mediaLike: false)
        model.didMount(generic)
        await model.waitForScan(generic.id)
        let card = MountedCard(url: f.root.appendingPathComponent("card"), name: "SD-CARD", volumeUUID: "card-uuid")
        model.didMount(card)
        await model.waitForScan(card.id)
        // The generic disk arrived first, yet the removable card must lead the list.
        #expect(model.drafts.map(\.volume.name) == ["SD-CARD", "SSD-DEST"])
    }
}
