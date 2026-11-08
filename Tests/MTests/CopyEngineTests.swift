import Foundation
import Testing
@testable import M

struct CopyEngineTests {
    @Test func preservesSymbolicLinksWithoutReadingTheirTargets() async throws {
        let f = try Fixture()
        try f.put("source/DCIM/a.JPG")
        try f.put("outside.txt", Data("do not follow".utf8))
        let link = f.root.appendingPathComponent("source/DCIM/support-link")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "../../outside.txt")
        let source = f.root.appendingPathComponent("source")
        let scan = try ScanEngine.scan(root: source)
        let destination = f.root.appendingPathComponent("out")
        let outcome = await CopyEngine().run(CopyRequest(sourceRoot: source, destinationRoot: destination, volumeUUID: "A", sessionID: UUID(), folders: scan.folders, applyFinderTag: false, preventSleep: false), ledgerEntries: []) { _ in }
        #expect(outcome.status == .completata)
        #expect(outcome.fileCount == 2)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: destination.appendingPathComponent("DCIM/support-link").path) == "../../outside.txt")
        #expect(try String(contentsOf: f.root.appendingPathComponent("outside.txt"), encoding: .utf8) == "do not follow")
    }

    @Test func copiesWholeTreeAndSkipsRegisteredFiles() async throws {
        let f = try Fixture()
        try f.put("source/DCIM/a.JPG", Data(repeating: 4, count: 1_100_000))
        try f.put("source/DCIM/sidecar.txt")
        try FileManager.default.createDirectory(at: f.root.appendingPathComponent("source/DCIM/empty"), withIntermediateDirectories: true)
        let source = f.root.appendingPathComponent("source")
        let scan = try ScanEngine.scan(root: source)
        let destination = f.root.appendingPathComponent("out")
        let request = CopyRequest(sourceRoot: source, destinationRoot: destination, volumeUUID: "A", sessionID: UUID(), folders: scan.folders, applyFinderTag: false, preventSleep: false)
        let first = await CopyEngine().run(request, ledgerEntries: []) { _ in }
        #expect(first.status == .completata)
        #expect(first.fileCount == 2)
        #expect(first.entries.count == 2)
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("DCIM/empty").path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
        #expect(try Data(contentsOf: destination.appendingPathComponent("DCIM/a.JPG")) == Data(contentsOf: source.appendingPathComponent("DCIM/a.JPG")))
        let second = await CopyEngine().run(request, ledgerEntries: first.entries) { _ in }
        #expect(second.skippedCount == 2)
        #expect(second.fileCount == 0)
        #expect(second.status == .completata)
    }
}
