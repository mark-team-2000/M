import AppKit
import Foundation

struct MountedCard: Identifiable, Equatable, Sendable {
    var id: String { url.path }
    let url: URL
    let name: String
    let volumeUUID: String

    static func read(_ url: URL) throws -> MountedCard? {
        let values = try url.resourceValues(forKeys: [.volumeIsRemovableKey, .volumeIsEjectableKey, .volumeUUIDStringKey, .volumeNameKey, .volumeTotalCapacityKey])
        guard values.volumeIsRemovable == true || values.volumeIsEjectable == true else { return nil }
        let name = values.volumeName ?? url.lastPathComponent
        // Some FAT/exFAT volumes do not publish a persistent UUID. The required
        // name+capacity fallback is weaker (two identical cards can collide).
        let identity = values.volumeUUIDString ?? "fallback:\(name):\(values.volumeTotalCapacity ?? 0)"
        return MountedCard(url: url, name: name, volumeUUID: identity)
    }
}

@MainActor
final class CardWatcher {
    var onMount: ((MountedCard) -> Void)?
    var onUnmount: ((MountedCard) -> Void)?
    private var known: [String: MountedCard] = [:]
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        // NSWorkspace exposes notificationCenter, not notificationQueue.
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { [weak self] note in
            let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL
            Task { @MainActor in
                guard let self else { return }
                if let url { self.checkMountedURL(url, forceRemount: true) }
                self.poll()
            }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main) { [weak self] note in
            let path = (note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL)?.path
            Task { @MainActor in
                guard let self else { return }
                if let path, let card = self.known.removeValue(forKey: path) { self.onUnmount?(card) }
                self.poll()
            }
        })
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        poll()
    }
    func stop() {
        timer?.invalidate(); timer = nil
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
        known.removeAll()
    }
    private func checkMountedURL(_ url: URL, forceRemount: Bool) {
        guard let card = try? MountedCard.read(url) else { return }
        if let old = known[card.id] {
            if old.volumeUUID != card.volumeUUID || forceRemount {
                onUnmount?(old)
                known[card.id] = card
                onMount?(card)
            }
        } else {
            known[card.id] = card
            onMount?(card)
        }
    }
    private func poll() {
        guard let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeIsRemovableKey, .volumeIsEjectableKey], options: []) else { return }
        let paths = Set(urls.map(\.path))
        for path in Array(known.keys) where !paths.contains(path) {
            if let card = known.removeValue(forKey: path) { onUnmount?(card) }
        }
        for url in urls { checkMountedURL(url, forceRemount: false) }
    }
}
