import SwiftUI

/// Shared semantic colors deliberately support both system appearances.
enum Theme {
    static let accent = Color(red: 0.96, green: 0.29, blue: 0.34)
    static let success = Color(red: 0.23, green: 0.76, blue: 0.53)
    static func bytes(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .decimal) }
    static func gb(_ value: Int64) -> String { String(format: "%.2f GB", Double(value) / 1_000_000_000) }
}

struct Surface<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(.primary.opacity(0.07), lineWidth: 1) }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white).padding(.horizontal, 22).padding(.vertical, 13)
            .background(LinearGradient(colors: [Theme.accent, Color(red: 0.78, green: 0.14, blue: 0.23)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 12))
            .opacity(!enabled ? 0.4 : configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct RedTag: View {
    let count: Int
    var body: some View {
        Label("\(count) già scaricati", systemImage: "circle.fill")
            .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.accent)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(Theme.accent.opacity(0.10), in: Capsule())
            .accessibilityLabel("\(count) file già scaricati, tag rosso")
    }
}

struct StatusBadge: View {
    let status: CardStatus
    var color: Color {
        switch status { case .completata: return Theme.success; case .inCorso: return Theme.accent; case .parziale: return .orange; case .fallita: return .red }
    }
    var symbol: String {
        switch status { case .completata: return "checkmark.circle.fill"; case .inCorso: return "arrow.down.circle.fill"; case .parziale: return "pause.circle.fill"; case .fallita: return "exclamationmark.circle.fill" }
    }
    var body: some View {
        Label(status.title, systemImage: symbol).font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color).padding(.horizontal, 9).padding(.vertical, 5).background(color.opacity(0.12), in: Capsule())
    }
}

struct Metric: View {
    let title: String
    let value: String
    let symbol: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.title3).foregroundStyle(Theme.accent).frame(width: 36, height: 36).background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(value).font(.system(size: 19, weight: .semibold, design: .rounded)).monospacedDigit()
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}
