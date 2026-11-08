import Foundation
import Testing
@testable import M

struct LedgerTests {
    @Test func exactIdentitySkipsButChangedSizeDateOrVolumeCopies() {
        let date = Date(timeIntervalSince1970: 1000)
        let entry = LedgerEntry(volumeUUID: "card-A", relativePath: "DCIM/a.jpg", size: 42, sourceModified: date, sessionID: UUID(), copiedAt: date)
        let ledger = Ledger(entries: [entry])
        #expect(ledger.contains(volumeUUID: "card-A", file: ScannedFile(relativePath: "DCIM/a.jpg", size: 42, modified: date, isMedia: true)))
        #expect(!ledger.contains(volumeUUID: "card-A", file: ScannedFile(relativePath: "DCIM/a.jpg", size: 43, modified: date, isMedia: true)))
        #expect(!ledger.contains(volumeUUID: "card-B", file: ScannedFile(relativePath: "DCIM/a.jpg", size: 42, modified: date, isMedia: true)))
        #expect(!ledger.contains(volumeUUID: "card-A", file: ScannedFile(relativePath: "DCIM/a.jpg", size: 42, modified: date.addingTimeInterval(1), isMedia: true)))
    }
}
