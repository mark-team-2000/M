import Foundation

enum ReportWriter {
    static func write(session: SessionRecord, cards: [CardRecord], at date: Date = Date()) throws -> URL {
        let container = URL(fileURLWithPath: session.destinationPath, isDirectory: true)
        try DestinationCheck.validate(container, requiredBytes: 0)
        // V1 ruling: the report lives inside the session folder, not the container.
        let destination = session.folderURL
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let url = destination.appendingPathComponent("REPORT-\(FolderNaming.sanitize(session.name, volumeName: "Sessione")).md")
        func safe(_ text: String) -> String { text.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "`", with: "’") }
        let iso = ISO8601DateFormatter()
        var text = "# M · \(safe(session.name))\n\nData report: \(iso.string(from: date))\n\nCartella sessione: `\(safe(destination.path))`\n\n"
        text += "Tessere: \(cards.count) · File copiati e verificati: \(cards.reduce(0) { $0 + $1.fileCount }) · Byte copiati: \(cards.reduce(Int64(0)) { $0 + $1.copiedBytes }) · Già scaricati: \(cards.reduce(0) { $0 + $1.skippedCount })\n\nVerifica integrità: dimensione sorgente = dimensione destinazione (non checksum).\n\n"
        for card in cards.sorted(by: { $0.startedAt < $1.startedAt }) {
            text += "## \(safe(card.folderName)) · \(card.status.title)\n\n"
            text += "- Volume: \(safe(card.volumeName))\n- Identificatore: `\(safe(card.volumeUUID))`\n- Destinazione: `\(safe(card.destPath))`\n- Inizio: \(iso.string(from: card.startedAt))\n- Fine: \(card.finishedAt.map { iso.string(from: $0) } ?? "in corso")\n- File copiati: \(card.fileCount)\n- Byte verificati: \(card.copiedBytes)\n- Già scaricati: \(card.skippedCount)\n"
            if card.errors.isEmpty { text += "- Errori: nessuno\n\n" }
            else { text += "- Errori:\n" + card.errors.map { "  - \(safe($0))" }.joined(separator: "\n") + "\n\n" }
        }
        try Data(text.utf8).write(to: url, options: .atomic)
        return url
    }
}
