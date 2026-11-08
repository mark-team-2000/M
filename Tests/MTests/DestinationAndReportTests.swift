import Foundation
import Testing
@testable import M

struct DestinationAndReportTests {
    @Test func missingDestinationAndInsufficientSpaceAreRejected() throws {
        let f = try Fixture()
        #expect(throws: (any Error).self) { try DestinationCheck.validate(f.root.appendingPathComponent("missing"), requiredBytes: 0) }
        #expect(throws: (any Error).self) { try DestinationCheck.validate(f.root, requiredBytes: 100, capacity: { _ in 99 }) }
        try DestinationCheck.validate(f.root, requiredBytes: 100, capacity: { _ in 100 })
    }
    @Test func reportIncludesCardsBytesAndErrorsInDestination() throws {
        let f = try Fixture()
        let session = SessionRecord(name: "Viaggio/2026", destinationPath: f.root.path)
        let card = CardRecord(sessionID: session.id, volumeName: "SD", volumeUUID: "A", folderName: "Giorno 1", destPath: "out", status: .parziale, fileCount: 2, copiedBytes: 300, skippedCount: 1, errors: ["Errore fixture"])
        let url = try ReportWriter.write(session: session, cards: [card])
        #expect(url.lastPathComponent == "REPORT-Viaggio_2026.md")
        // V1 ruling: the report lives inside the session folder inside the container.
        #expect(url.deletingLastPathComponent().lastPathComponent == "Viaggio_2026")
        #expect(url.deletingLastPathComponent().deletingLastPathComponent().path == f.root.path)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("300"))
        #expect(text.contains("Errore fixture"))
        #expect(text.contains("Giorno 1"))
    }
}
