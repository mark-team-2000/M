import Foundation

struct Ledger: Sendable {
    private struct Key: Hashable, Sendable {
        let volume: String
        let path: String
        let size: Int64
        let modified: Date
    }
    private var keys: Set<Key>
    init(entries: [LedgerEntry]) {
        keys = Set(entries.map { Key(volume: $0.volumeUUID, path: $0.relativePath, size: $0.size, modified: $0.sourceModified) })
    }
    func contains(volumeUUID: String, file: ScannedFile) -> Bool {
        keys.contains(Key(volume: volumeUUID, path: file.relativePath, size: file.size, modified: file.modified))
    }
    mutating func insert(_ entry: LedgerEntry) {
        keys.insert(Key(volume: entry.volumeUUID, path: entry.relativePath, size: entry.size, modified: entry.sourceModified))
    }
}
