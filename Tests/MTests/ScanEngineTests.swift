import Foundation
import Testing
@testable import M

final class Fixture: @unchecked Sendable {
    let root: URL
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("M-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: root) }
    @discardableResult func put(_ path: String, _ data: Data = Data("fixture".utf8)) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        return url
    }
}

struct ScanEngineTests {
    @Test func noMediaHasAnEmptyResultAndWavIsRecognized() throws {
        let f = try Fixture()
        try f.put("MISC/readme.txt")
        #expect(try ScanEngine.scan(root: f.root).folders.isEmpty)
        try f.put("AUDIO/deep/take.WAV")
        #expect(try ScanEngine.scan(root: f.root).folders.map(\.relativePath) == ["AUDIO"])
    }

    @Test func rootMediaPromotesRootAndPreservesHiddenSupportFiles() throws {
        let f = try Fixture()
        try f.put("root.MP4")
        try f.put("DCIM/nested/a.CR3")
        try f.put("MISC/readme.txt")
        try f.put("DCIM/.camera-note")
        try f.put(".Trashes/deleted.JPG")
        try f.put("DCIM/.private/hidden.JPG")
        let scan = try ScanEngine.scan(root: f.root)
        #expect(scan.folders.map(\.relativePath) == [""])
        #expect(scan.files.map(\.relativePath) == ["DCIM/.camera-note", "DCIM/nested/a.CR3", "MISC/readme.txt", "root.MP4"])
    }

    @Test func topLevelMediaFoldersIncludeSidecarsAndIgnoreSystem() throws {
        let f = try Fixture()
        try f.put("DCIM/100EOS/A.CR3")
        try f.put("DCIM/100EOS/A.JPG")
        try f.put("DCIM/100EOS/deep/A.MOV")
        try f.put("DCIM/notes.txt")
        try f.put("MISC/readme.txt")
        try f.put(".Trashes/trash.JPG")
        try f.put("__MACOSX/hidden.JPG")
        try f.put("lost+found/hidden.JPG")
        let scan = try ScanEngine.scan(root: f.root)
        #expect(scan.folders.map(\.relativePath) == ["DCIM"])
        #expect(scan.folders.first?.files.count == 4)
        #expect(scan.folders.first?.mediaCount == 3)
    }
}
