import Foundation
import Testing
@testable import M

struct StoreTests {
    @Test func jsonRoundTripAndCorruptionBackup() throws {
        let f = try Fixture()
        let url = f.root.appendingPathComponent("support/store.json")
        let repository = StoreRepository(url: url)
        let session = SessionRecord(name: "Viaggio", destinationPath: f.root.path)
        let card = CardRecord(sessionID: session.id, volumeName: "EOS", volumeUUID: "uuid", folderName: "Giorno 1", destPath: f.root.path, status: .completata)
        let entry = LedgerEntry(volumeUUID: "uuid", relativePath: "DCIM/a.jpg", size: 7, sourceModified: Date(timeIntervalSince1970: 1_000), sessionID: session.id, copiedAt: Date())
        let original = Store(sessions: [session], cards: [card], ledger: [entry])
        try repository.save(original)
        let loaded = try repository.load().store
        #expect(loaded.sessions.first?.name == "Viaggio")
        #expect(loaded.cards.first?.status == .completata)
        #expect(loaded.ledger.first?.sourceModified == entry.sourceModified)
        let corrupt = Data("not JSON".utf8)
        try corrupt.write(to: url)
        let recovered = try repository.load()
        #expect(recovered.store.sessions.isEmpty)
        #expect(recovered.warning != nil)
        #expect(try Data(contentsOf: url.deletingLastPathComponent().appendingPathComponent("store.corrupt.json")) == corrupt)
        #expect(try repository.load().store.sessions.isEmpty)
    }
}
