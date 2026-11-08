import Foundation
import Testing
@testable import M

struct CapCutDraftFactoryTests {
    struct Fixture {
        let root: URL
        let layout: CapCutDraftFactory.Layout
        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("capcut-fixture-\(UUID().uuidString)")
            let fm = FileManager.default
            layout = CapCutDraftFactory.Layout(capCutRoot: root.appendingPathComponent("Movies/CapCut"))
            try fm.createDirectory(at: layout.draftsFolder.appendingPathComponent("Vecchio"), withIntermediateDirectories: true)
            try fm.createDirectory(at: layout.registryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let content: [String: Any] = [
                "version": 360000, "name": "", "path": "", "id": "OLDID", "duration": 999,
                "materials": ["videos": [["id": "v1"]], "audios": [], "canvases": [["id": "c1"]]],
                "tracks": [["segments": [["id": "s1"]]]],
                "keyframes": ["videos": [["k": 1]]],
            ]
            let meta: [String: Any] = [
                "draft_id": "OLDID", "draft_name": "Vecchio",
                "draft_fold_path": layout.draftsFolder.appendingPathComponent("Vecchio").path,
                "draft_root_path": layout.draftsFolder.path,
                "draft_cover": "draft_cover.jpg", "draft_materials": [["type": 0]],
                "draft_timeline_materials_size_": 123, "tm_draft_create": 111,
            ]
            let data = try JSONSerialization.data(withJSONObject: content)
            try data.write(to: layout.draftsFolder.appendingPathComponent("Vecchio/draft_content.json"))
            try JSONSerialization.data(withJSONObject: meta).write(to: layout.draftsFolder.appendingPathComponent("Vecchio/draft_meta_info.json"))
            let registry: [String: Any] = ["all_draft_store": [meta], "draft_ids": 1, "root_path": "x"]
            try JSONSerialization.data(withJSONObject: registry).write(to: layout.registryURL)
        }
        func registry() throws -> (store: [[String: Any]], ids: Int) {
            let object = try JSONSerialization.jsonObject(with: Data(contentsOf: layout.registryURL)) as! [String: Any]
            return (object["all_draft_store"] as! [[String: Any]], object["draft_ids"] as! Int)
        }
        func json(at url: URL) throws -> [String: Any] { try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any] }
    }

    @Test func createsEmptyDraftFromDonorAndRegistersIt() throws {
        let f = try Fixture()
        let folder = try CapCutDraftFactory.createDraft(named: "Matrimonio", in: f.layout, running: false)
        #expect(folder.lastPathComponent == "Matrimonio")
        let content = try f.json(at: folder.appendingPathComponent("draft_content.json"))
        #expect((content["tracks"] as? [Any])?.isEmpty == true)
        #expect(content["duration"] as? Int == 0)
        let materials = content["materials"] as! [String: Any]
        for (key, value) in materials { #expect((value as? [Any])?.isEmpty == true, "materials.\(key) not emptied") }
        #expect((content["keyframes"] as! [String: Any])["videos"] as? [Any] != nil)
        #expect(((content["keyframes"] as! [String: Any])["videos"] as? [Any])?.isEmpty == true)
        #expect((content["id"] as? String) != "OLDID")
        let meta = try f.json(at: folder.appendingPathComponent("draft_meta_info.json"))
        #expect(meta["draft_name"] as? String == "Matrimonio")
        #expect(meta["draft_fold_path"] as? String == folder.path)
        #expect(meta["draft_id"] as? String == content["id"] as? String)
        #expect(meta["draft_timeline_materials_size_"] as? Int == 0)
        let registry = try f.registry()
        #expect(registry.store.count == 2)
        #expect(registry.ids == 2)
        #expect(registry.store.last?["draft_name"] as? String == "Matrimonio")
        // Donor untouched.
        let donor = try f.json(at: f.layout.draftsFolder.appendingPathComponent("Vecchio/draft_content.json"))
        #expect(((donor["materials"] as! [String: Any])["videos"] as? [Any])?.count == 1)
        // Registry backed up.
        let backups = try FileManager.default.contentsOfDirectory(at: f.layout.capCutRoot, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.contains("m-backup") }
        #expect(backups.count == 1)
    }

    @Test func refusesWhileCapCutIsRunningAndTouchesNothing() throws {
        let f = try Fixture()
        let before = try f.registry()
        #expect(throws: CapCutDraftError.capCutRunning) {
            _ = try CapCutDraftFactory.createDraft(named: "X", in: f.layout, running: true)
        }
        let after = try f.registry()
        #expect(after.store.count == before.store.count)
        #expect(!FileManager.default.fileExists(atPath: f.layout.draftsFolder.appendingPathComponent("X").path))
    }

    @Test func collisionGetsNumberSuffixAndCorruptRegistryRefuses() throws {
        let f = try Fixture()
        _ = try CapCutDraftFactory.createDraft(named: "Reel", in: f.layout, running: false)
        let second = try CapCutDraftFactory.createDraft(named: "Reel", in: f.layout, running: false)
        #expect(second.lastPathComponent == "Reel 2")
        try Data("non-json".utf8).write(to: f.layout.registryURL)
        #expect(throws: CapCutDraftError.registryCorrupt) {
            _ = try CapCutDraftFactory.createDraft(named: "Reel", in: f.layout, running: false)
        }
    }
}
