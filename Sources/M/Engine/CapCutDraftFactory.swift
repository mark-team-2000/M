import AppKit
import Foundation

/// V7 ruling: M creates REAL CapCut draft projects on disk, mirroring the layout CapCut
/// itself uses (folder + draft_content.json + draft_meta_info.json + entry in the global
/// registry). Strategy: take the most recently modified existing draft as a SCHEMA DONOR,
/// strip every material/track to empty, and give the copy a fresh identity. Never touches
/// any existing draft; the registry gets a timestamped backup and an atomic rewrite.
enum CapCutDraftError: LocalizedError {
    case notInstalled
    case capCutRunning
    case noDonor
    case registryCorrupt

    var errorDescription: String? {
        switch self {
        case .notInstalled: return "CapCut non risulta installato (manca «Movies/CapCut/CapCut Drafts»)."
        case .capCutRunning: return "CapCut è aperto e sovrascriverebbe il registro: chiudilo e ripremi «Apri CapCut»."
        case .noDonor: return "Nessun progetto CapCut esistente da usare come modello di struttura."
        case .registryCorrupt: return "Il registro dei progetti di CapCut non è leggibile: nessuna scrittura tentata."
        }
    }
}

struct CapCutDraftFactory {
    struct Layout: Equatable {
        let capCutRoot: URL
        var draftsFolder: URL { capCutRoot.appendingPathComponent("CapCut Drafts", isDirectory: true) }
        var registryURL: URL { capCutRoot.appendingPathComponent("User Data/Projects/com.lveditor.draft/root_meta_info.json") }
    }

    static func installedLayout(fileManager fm: FileManager = .default) -> Layout? {
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent("Movies/CapCut", isDirectory: true)
        return fm.fileExists(atPath: root.appendingPathComponent("CapCut Drafts", isDirectory: true).path) ? Layout(capCutRoot: root) : nil
    }

    static func isCapCutRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.lemon.lvoverseas" }
    }

    /// Creates a fresh empty draft named after the session. `running` is injected so tests
    /// can exercise the guard without a real CapCut. Returns the new draft folder URL.
    @discardableResult
    static func createDraft(named requestedName: String, in layout: Layout, running: Bool,
                            fileManager fm: FileManager = .default, now: Date = Date()) throws -> URL {
        guard !running else { throw CapCutDraftError.capCutRunning }
        guard let registry = try? Data(contentsOf: layout.registryURL),
              var registryObject = (try? JSONSerialization.jsonObject(with: registry)) as? [String: Any],
              var store = registryObject["all_draft_store"] as? [[String: Any]]
        else { throw CapCutDraftError.registryCorrupt }

        // Schema donor: newest existing draft with readable content + meta.
        let draftsOnDisk = store.compactMap { entry -> (URL, Date)? in
            guard let path = entry["draft_fold_path"] as? String else { return nil }
            let url = URL(fileURLWithPath: path)
            let content = url.appendingPathComponent("draft_content.json")
            guard let date = try? fm.attributesOfItem(atPath: url.path)[.modificationDate] as? Date,
                  fm.fileExists(atPath: content.path), fm.fileExists(atPath: url.appendingPathComponent("draft_meta_info.json").path)
            else { return nil }
            return (url, date)
        }.sorted { $0.1 > $1.1 }
        guard let donorFolder = draftsOnDisk.first?.0,
              let donorContent = (try? JSONSerialization.jsonObject(with: Data(contentsOf: donorFolder.appendingPathComponent("draft_content.json")))) as? [String: Any],
              var donorMeta = (try? JSONSerialization.jsonObject(with: Data(contentsOf: donorFolder.appendingPathComponent("draft_meta_info.json")))) as? [String: Any]
        else { throw CapCutDraftError.noDonor }

        // Reserve a collision-free folder/name (CapCut itself uses " 2" suffixes).
        let base = sanitize(requestedName)
        var name = base
        var folder = layout.draftsFolder.appendingPathComponent(name, isDirectory: true)
        var counter = 2
        while fm.fileExists(atPath: folder.path) {
            name = "\(base) \(counter)"
            folder = layout.draftsFolder.appendingPathComponent(name, isDirectory: true)
            counter += 1
        }

        // Empty the donor content: every material list cleared, no tracks, fresh identity.
        var content = donorContent
        if var materials = content["materials"] as? [String: Any] {
            for (key, value) in materials where value is [Any] { materials[key] = [Any]() }
            content["materials"] = materials
        }
        if var keyframes = content["keyframes"] as? [String: Any] {
            for (key, value) in keyframes where value is [Any] { keyframes[key] = [Any]() }
            content["keyframes"] = keyframes
        }
        let draftID = UUID().uuidString
        content["tracks"] = [[String: Any]]()
        content["duration"] = 0
        content["id"] = draftID
        content["create_time"] = 0
        content["update_time"] = 0
        content["name"] = ""
        content["path"] = ""

        // Meta: donor shape with fresh identity and zeroed material bookkeeping.
        let seconds = Int(now.timeIntervalSince1970)
        donorMeta["draft_id"] = draftID
        donorMeta["draft_name"] = name
        donorMeta["draft_fold_path"] = folder.path
        donorMeta["draft_root_path"] = layout.draftsFolder.path
        donorMeta["draft_cover"] = ""
        donorMeta["draft_materials"] = [[String: Any]]()
        donorMeta["draft_timeline_materials_size_"] = 0
        donorMeta["tm_draft_create"] = seconds
        donorMeta["tm_draft_modified"] = seconds

        try fm.createDirectory(at: folder, withIntermediateDirectories: false)
        let jsonOptions: JSONSerialization.WritingOptions = [.withoutEscapingSlashes]
        try JSONSerialization.data(withJSONObject: content, options: jsonOptions).write(to: folder.appendingPathComponent("draft_content.json"))
        try JSONSerialization.data(withJSONObject: donorMeta, options: jsonOptions).write(to: folder.appendingPathComponent("draft_meta_info.json"))
        try "[General]\ncloud_last_modify_platform=mac\ndraft_create_time=\(seconds)\ndraft_last_edit_time=\(seconds)\nreal_edit_keys=0\nreal_edit_seconds=0\n"
            .write(to: folder.appendingPathComponent("draft_settings"), atomically: true, encoding: .utf8)
        for (name, data) in [("draft_agency_config.json", Data(#"{"is_auto_agency_enabled":false,"is_auto_agency_popup":false,"is_single_agency_mode":false,"marterials":null,"use_converter":false,"video_resolution":720}"#.utf8)),
                             ("draft_biz_config.json", Data())] {
            try data.write(to: folder.appendingPathComponent(name))
        }
        // Carry over static per-install defaults the editor expects to find (generic, no project data).
        for staticName in ["attachment_pc_common.json"] {
            if let data = try? Data(contentsOf: donorFolder.appendingPathComponent(staticName)) {
                try data.write(to: folder.appendingPathComponent(staticName))
            }
        }

        // Registry: backup once, append the entry (CapCut stores the same meta shape there), atomic rewrite.
        store.append(donorMeta)
        registryObject["all_draft_store"] = store
        if let count = registryObject["draft_ids"] as? Int { registryObject["draft_ids"] = count + 1 }
        try layout.registryURL.copy(to: layout.capCutRoot.appendingPathComponent("root_meta_info.m-backup-\(seconds).json"), fm: fm)
        try JSONSerialization.data(withJSONObject: registryObject, options: jsonOptions).write(to: layout.registryURL, options: .atomic)
        return folder
    }

    private static func sanitize(_ name: String) -> String {
        let clean = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? "Progetto" : clean
    }
}

private extension URL {
    func copy(to destination: URL, fm: FileManager) throws {
        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        try fm.copyItem(at: self, to: destination)
    }
}
