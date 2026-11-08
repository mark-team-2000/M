import Foundation

struct SessionRecord: Codable, Identifiable, Sendable {
    var id: UUID = UUID()
    var name: String
    var destinationPath: String
    var createdAt: Date = Date()
    var cardIDs: [UUID] = []
    /// Actual session folder created INSIDE destinationPath (V1 founder ruling).
    /// nil only for stores saved before the ruling: derived from the name on first use.
    var folderPath: String?
    /// V3: archived sessions keep their history but never receive new cards.
    /// Optional so stores saved before the ruling still decode.
    var archived: Bool?
    var isArchived: Bool { archived == true }
    var folderURL: URL {
        if let folderPath { return URL(fileURLWithPath: folderPath, isDirectory: true) }
        return URL(fileURLWithPath: destinationPath, isDirectory: true)
            .appendingPathComponent(FolderNaming.sanitize(name, volumeName: "SESSIONE"), isDirectory: true)
    }
}

enum CardStatus: String, Codable, Sendable {
    case inCorso, completata, parziale, fallita
    var title: String {
        switch self {
        case .inCorso: return "In corso"
        case .completata: return "Completata"
        case .parziale: return "Parziale"
        case .fallita: return "Fallita"
        }
    }
}

struct CardRecord: Codable, Identifiable, Sendable {
    var id: UUID = UUID()
    var sessionID: UUID
    var volumeName: String
    var volumeUUID: String
    var folderName: String
    var destPath: String
    var startedAt: Date = Date()
    var finishedAt: Date?
    var status: CardStatus = .inCorso
    var fileCount: Int = 0
    var copiedBytes: Int64 = 0
    var skippedCount: Int = 0
    var errors: [String] = []
}

struct LedgerEntry: Codable, Sendable {
    var volumeUUID: String
    var relativePath: String
    var size: Int64
    var sourceModified: Date
    var sessionID: UUID
    var copiedAt: Date
}

struct Store: Codable, Sendable {
    var sessions: [SessionRecord] = []
    var cards: [CardRecord] = []
    var ledger: [LedgerEntry] = []
}
