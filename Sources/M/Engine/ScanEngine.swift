import Foundation

struct ScannedFile: Identifiable, Hashable, Sendable {
    var id: String { relativePath }
    let relativePath: String
    let size: Int64
    let modified: Date
    let isMedia: Bool
    var symbolicLinkTarget: String? = nil
}

struct MediaFolder: Identifiable, Sendable {
    var id: String { relativePath }
    let relativePath: String // Empty string denotes the volume root.
    let files: [ScannedFile]
    let directories: [String]
    var byteCount: Int64 { files.reduce(0) { $0 + $1.size } }
    var mediaCount: Int { files.filter(\.isMedia).count }
    var displayName: String { relativePath.isEmpty ? "Intera scheda" : relativePath }
}

struct ScanResult: Sendable {
    let folders: [MediaFolder]
    var files: [ScannedFile] { folders.flatMap(\.files) }
}

enum ScanEngine {
    static let mediaExtensions: Set<String> = ["jpg", "jpeg", "heic", "heif", "nef", "cr2", "cr3", "arw", "raf", "dng", "orf", "rw2", "gpr", "raw", "mp4", "mov", "mxf", "avi", "wav"]
    static func ignored(_ name: String) -> Bool {
        name.hasPrefix(".") || name == "lost+found" || name == "__MACOSX"
    }

    /// Maximal folders are the top-level media-bearing branches. A root media
    /// file promotes the whole volume (excluding system paths) to one folder.
    static func scan(root: URL) throws -> ScanResult {
        let fm = FileManager.default
        let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL
        var files: [ScannedFile] = []
        var directories: [String] = []
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        var enumerationError: Error?
        guard let walker = fm.enumerator(at: resolvedRoot, includingPropertiesForKeys: keys, options: [], errorHandler: { _, error in
            enumerationError = error
            return false
        }) else { throw IngestError.message("Impossibile leggere la scheda.") }
        let prefix = resolvedRoot.path.hasSuffix("/") ? resolvedRoot.path : resolvedRoot.path + "/"
        for case let url as URL in walker {
            try Task.checkCancellation()
            let values = try url.resourceValues(forKeys: Set(keys))
            if values.isDirectory == true && ignored(url.lastPathComponent) { walker.skipDescendants(); continue }
            // Copy links as links, never follow them off-card or through cycles.
            if values.isSymbolicLink == true {
                walker.skipDescendants()
                let path = url.standardizedFileURL.path
                guard path.hasPrefix(prefix) else { throw IngestError.message("Percorso esterno alla scheda.") }
                let attrs = try fm.attributesOfItem(atPath: url.path)
                files.append(ScannedFile(relativePath: String(path.dropFirst(prefix.count)), size: (attrs[.size] as? NSNumber)?.int64Value ?? 0, modified: attrs[.modificationDate] as? Date ?? .distantPast, isMedia: mediaExtensions.contains(url.pathExtension.lowercased()), symbolicLinkTarget: try fm.destinationOfSymbolicLink(atPath: url.path)))
                continue
            }
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(prefix) else { throw IngestError.message("Percorso esterno alla scheda.") }
            let relative = String(path.dropFirst(prefix.count))
            if values.isDirectory == true { directories.append(relative); continue }
            guard values.isRegularFile == true else { continue }
            files.append(ScannedFile(relativePath: relative, size: Int64(values.fileSize ?? 0), modified: values.contentModificationDate ?? .distantPast, isMedia: mediaExtensions.contains(url.pathExtension.lowercased())))
        }
        if let error = enumerationError { throw error }
        files.sort { $0.relativePath < $1.relativePath }
        let media = files.filter(\.isMedia)
        if media.contains(where: { !$0.relativePath.contains("/") }) {
            return ScanResult(folders: [MediaFolder(relativePath: "", files: files, directories: directories.sorted())])
        }
        let branches = Set(media.compactMap { $0.relativePath.split(separator: "/").first.map(String.init) })
        return ScanResult(folders: branches.sorted().map { branch in
            MediaFolder(relativePath: branch, files: files.filter { $0.relativePath.hasPrefix(branch + "/") }, directories: directories.filter { $0 == branch || $0.hasPrefix(branch + "/") }.sorted())
        })
    }
}

enum IngestError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}
