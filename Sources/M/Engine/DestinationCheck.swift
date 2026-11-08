import Foundation

enum DestinationCheck {
    static func validate(_ url: URL, requiredBytes: Int64, capacity: (URL) throws -> Int64 = { url in
        let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityKey])
        guard let bytes = values.volumeAvailableCapacity else { throw IngestError.message("Impossibile verificare lo spazio disponibile nella destinazione.") }
        return Int64(bytes)
    }) throws {
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory), directory.boolValue else {
            throw IngestError.message("La cartella di destinazione non esiste più. Ricollega il disco oppure crea una nuova sessione.")
        }
        guard FileManager.default.isWritableFile(atPath: url.path) else { throw IngestError.message("La cartella di destinazione non è scrivibile.") }
        let free = try capacity(url)
        guard free >= requiredBytes else {
            throw IngestError.message("Spazio insufficiente: servono \(ByteCountFormatter.string(fromByteCount: requiredBytes, countStyle: .file)), disponibili \(ByteCountFormatter.string(fromByteCount: free, countStyle: .file)).")
        }
    }
}
