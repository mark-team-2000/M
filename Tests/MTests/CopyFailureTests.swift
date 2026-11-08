import Foundation
import Testing
@testable import M

private actor ChunkGate {
    private var entered = false
    private var paused: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?
    func pauseOnce() async {
        guard !entered else { return }
        entered = true
        await withCheckedContinuation { continuation in
            paused = continuation
            observer?.resume(); observer = nil
        }
    }
    func waitUntilPaused() async {
        if entered { return }
        await withCheckedContinuation { observer = $0 }
    }
    func release() { paused?.resume(); paused = nil }
}

struct CopyFailureTests {
    @Test func simulatedSizeMismatchDoesNotRegisterAndKeepsSourceIntact() async throws {
        let f = try Fixture()
        let data = Data(repeating: 19, count: 8192)
        let original = try f.put("source/DCIM/a.JPG", data)
        let source = f.root.appendingPathComponent("source")
        let scan = try ScanEngine.scan(root: source)
        let destination = f.root.appendingPathComponent("out")
        let result = await CopyEngine(destinationSize: { _ in -1 }).run(CopyRequest(sourceRoot: source, destinationRoot: destination, volumeUUID: "A", sessionID: UUID(), folders: scan.folders, applyFinderTag: false, preventSleep: false), ledgerEntries: []) { _ in }
        #expect(result.status == .fallita)
        #expect(result.entries.isEmpty)
        #expect(result.errors.count == 1)
        #expect(result.errors[0].contains("dimensione"))
        #expect(try Data(contentsOf: original) == data)
        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("DCIM/a.JPG").path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: destination.appendingPathComponent("DCIM").path).isEmpty)
    }

    @Test(.timeLimit(.minutes(1))) func cancellationKeepsVerifiedFilesAndRemovesIncompleteFile() async throws {
        let f = try Fixture()
        let first = try f.put("source/DCIM/a.JPG")
        let payload = Data(repeating: 8, count: 3_000_000)
        let second = try f.put("source/DCIM/b.MOV", payload)
        let source = f.root.appendingPathComponent("source")
        let scan = try ScanEngine.scan(root: source)
        let destination = f.root.appendingPathComponent("out")
        let gate = ChunkGate()
        let task = Task {
            await CopyEngine().run(CopyRequest(sourceRoot: source, destinationRoot: destination, volumeUUID: "A", sessionID: UUID(), folders: scan.folders, applyFinderTag: false, preventSleep: false), ledgerEntries: []) { event in
                if case .progress(let p) = event, p.currentFile == "DCIM/b.MOV", p.currentFileBytes > 0 { await gate.pauseOnce() }
            }
        }
        await gate.waitUntilPaused()
        task.cancel()
        await gate.release()
        let result = await task.value
        #expect(result.status == .parziale)
        #expect(result.fileCount == 1)
        #expect(result.entries.count == 1)
        #expect(try Data(contentsOf: destination.appendingPathComponent("DCIM/a.JPG")) == Data(contentsOf: first))
        #expect(try Data(contentsOf: second) == payload)
        #expect(try FileManager.default.contentsOfDirectory(atPath: destination.appendingPathComponent("DCIM").path) == ["a.JPG"])
    }

    @Test(.timeLimit(.minutes(1))) func sourceMutationDuringCopyIsDetectedAfterStreamCloses() async throws {
        let f = try Fixture()
        let original = try f.put("source/a.MOV", Data(repeating: 3, count: 3_000_000))
        let source = f.root.appendingPathComponent("source")
        let scan = try ScanEngine.scan(root: source)
        let destination = f.root.appendingPathComponent("out")
        let gate = ChunkGate()
        let task = Task {
            await CopyEngine().run(CopyRequest(sourceRoot: source, destinationRoot: destination, volumeUUID: "A", sessionID: UUID(), folders: scan.folders, applyFinderTag: false, preventSleep: false), ledgerEntries: []) { event in
                if case .progress(let p) = event, p.currentFileBytes > 0 { await gate.pauseOnce() }
            }
        }
        await gate.waitUntilPaused()
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: original.path)
        await gate.release()
        let result = await task.value
        #expect(result.status == .fallita)
        #expect(result.entries.isEmpty)
        #expect(result.errors.first?.contains("sorgente è cambiata") == true)
    }

    @Test func rejectsDestinationInsideSourceAndNeverOverwritesExistingFiles() async throws {
        let f = try Fixture()
        try f.put("source/a.JPG")
        let source = f.root.appendingPathComponent("source")
        let scan = try ScanEngine.scan(root: source)
        let nested = await CopyEngine().run(CopyRequest(sourceRoot: source, destinationRoot: source.appendingPathComponent("bad"), volumeUUID: "A", sessionID: UUID(), folders: scan.folders, applyFinderTag: false, preventSleep: false), ledgerEntries: []) { _ in }
        #expect(nested.status == .fallita)
        #expect(!FileManager.default.fileExists(atPath: source.appendingPathComponent("bad").path))
        let sentinel = try f.put("out/a.JPG", Data("original destination".utf8))
        let result = await CopyEngine().run(CopyRequest(sourceRoot: source, destinationRoot: sentinel.deletingLastPathComponent(), volumeUUID: "A", sessionID: UUID(), folders: scan.folders, applyFinderTag: false, preventSleep: false), ledgerEntries: []) { _ in }
        #expect(result.status == .fallita)
        #expect(try String(contentsOf: sentinel, encoding: .utf8) == "original destination")
    }
}
