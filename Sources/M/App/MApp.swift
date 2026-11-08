import AppKit
import SwiftUI

@main
struct MApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()
    @AppStorage("appearance") private var appearance = "dark"
    /// V7: headless test entry — `M --capcut-draft <nome>` creates the draft and exits,
    /// no GUI. Used by the honest end-to-end prova.
    init() {
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--capcut-draft"), index + 1 < args.count {
            let name = args[index + 1]
            do {
                guard let layout = CapCutDraftFactory.installedLayout() else { throw CapCutDraftError.notInstalled }
                let folder = try CapCutDraftFactory.createDraft(named: name, in: layout, running: CapCutDraftFactory.isCapCutRunning())
                print("CREATO \(folder.path)")
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("ERRORE \(error.localizedDescription)\n".utf8))
                exit(1)
            }
        }
    }
    var body: some Scene {
        WindowGroup("M") {
            ContentView(model: model, appearance: $appearance)
                .frame(minWidth: 960, minHeight: 620)
                .preferredColorScheme(appearance == "system" ? nil : appearance == "light" ? .light : .dark)
                .tint(Theme.accent)
                .onAppear { delegate.model = model; model.start() }
        }
        .defaultSize(width: 1180, height: 800)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Nuova sessione…") { NotificationCenter.default.post(name: .newMSession, object: nil) }.keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}

extension Notification.Name { static let newMSession = Notification.Name("M.newSession") }

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.applicationIconImage = Self.icon()
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model, model.isCopying else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Uno scaricamento è in corso"
        alert.informativeText = "Se esci, M annulla la copia corrente e conserva solo i file già verificati. Potrai riprendere reinserendo la scheda."
        alert.addButton(withTitle: "Continua scaricamento")
        alert.addButton(withTitle: "Annulla ed esci")
        guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
        model.cancelCopy()
        Task {
            await model.waitForCurrentCopy()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
    static func icon() -> NSImage {
        let image = NSImage(size: NSSize(width: 128, height: 128))
        image.lockFocus()
        let shape = NSBezierPath(roundedRect: NSRect(x: 5, y: 5, width: 118, height: 118), xRadius: 29, yRadius: 29)
        NSGradient(starting: NSColor(calibratedRed: 0.82, green: 0.13, blue: 0.19, alpha: 1), ending: NSColor(calibratedRed: 0.25, green: 0.025, blue: 0.07, alpha: 1))?.draw(in: shape, angle: -65)
        let text = "M" as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 82, weight: .heavy), .foregroundColor: NSColor.white]
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: (128 - size.width) / 2, y: (128 - size.height) / 2 + 4), withAttributes: attributes)
        image.unlockFocus()
        return image
    }
}
