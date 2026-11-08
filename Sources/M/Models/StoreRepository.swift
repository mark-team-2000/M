import Foundation

struct StoreRepository: Sendable {
    let url: URL
    static var standard: StoreRepository {
        StoreRepository(url: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("M/store.json"))
    }
    struct Loaded {
        var store: Store
        var warning: String?
    }
    func load() throws -> Loaded {
        guard FileManager.default.fileExists(atPath: url.path) else { return Loaded(store: Store()) }
        let data = try Data(contentsOf: url)
        do { return Loaded(store: try JSONDecoder().decode(Store.self, from: data)) }
        catch {
            let backup = url.deletingLastPathComponent().appendingPathComponent("store.corrupt.json")
            // Do not discard the only copy if writing the backup fails.
            try data.write(to: backup, options: .atomic)
            let empty = Store()
            try save(empty)
            return Loaded(store: empty, warning: "Il registro era danneggiato. Backup salvato in store.corrupt.json; è stato creato un registro vuoto.")
        }
    }
    func save(_ store: Store) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(store).write(to: url, options: .atomic)
    }
}
