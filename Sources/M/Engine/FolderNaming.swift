import Foundation
import Darwin

enum FolderNaming {
    static func sanitize(_ name: String, volumeName: String) -> String {
        func clean(_ value: String) -> String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let forbidden = CharacterSet(charactersIn: "/:*?\"<>|").union(.controlCharacters).union(.newlines)
            let replaced = String(trimmed.unicodeScalars.map { forbidden.contains($0) ? "_" : String($0) }.joined().prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines)
            return replaced == "." || replaced == ".." ? "" : replaced
        }
        let result = clean(name)
        if !result.isEmpty { return result }
        let fallback = clean(volumeName)
        return fallback.isEmpty ? "SCHEDE" : fallback
    }

    /// mkdir is exclusive: another process cannot turn a collision into overwrite.
    static func reserve(in parent: URL, name: String) throws -> URL {
        let safeName = sanitize(name, volumeName: "SCHEDE")
        var index = 1
        while true {
            let suffix = index == 1 ? "" : " \(index)"
            let candidateName = String(safeName.prefix(max(1, 80 - suffix.count))) + suffix
            let candidate = parent.appendingPathComponent(candidateName, isDirectory: true)
            if mkdir(candidate.path, 0o755) == 0 { return candidate }
            if errno == EEXIST { index += 1; continue }
            throw IngestError.message("Impossibile creare la destinazione: \(String(cString: strerror(errno))).")
        }
    }
}
