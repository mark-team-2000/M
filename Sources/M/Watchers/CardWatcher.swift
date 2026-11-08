import AppKit
import Darwin
import Foundation

struct MountedCard: Identifiable, Equatable, Sendable {
    var id: String { url.path }
    let url: URL
    let name: String
    let volumeUUID: String
    /// True for classic removable/ejectable media (SD/SD-express readers, disk images).
    /// CFexpress Type B rides on NVMe/PCIe: many readers report the volume as fixed and
    /// not ejectable, so external non-internal disks also qualify (V2 ruling) but they
    /// surface in the UI only when they actually contain media folders.
    var mediaLike: Bool = true

    /// Ruling V2 (founder 08/11, «Non rileva le tessere CF express Type B»): accept
    /// removable/ejectable media OR an external disk (non-internal, non-network,
    /// browsable). Internal containers — boot volume included — can never qualify.
    static func isCardLike(removable: Bool?, ejectable: Bool?, isInternal: Bool?, network: Bool?, browsable: Bool?) -> Bool {
        if removable == true || ejectable == true { return true }
        return isInternal == false && network != true && browsable != false
    }

    static func read(_ url: URL) throws -> MountedCard? {
        let keys: Set<URLResourceKey> = [.volumeIsRemovableKey, .volumeIsEjectableKey, .volumeIsInternalKey, .volumeIsBrowsableKey, .volumeUUIDStringKey, .volumeNameKey, .volumeTotalCapacityKey]
        let values = try url.resourceValues(forKeys: keys)
        // Foundation exposes no network-volume resource key: MNT_LOCAL is the canonical check.
        var stats = statfs()
        let network = statfs(url.path, &stats) == 0 ? (stats.f_flags & UInt32(MNT_LOCAL)) == 0 : nil
        let mediaLike = values.volumeIsRemovable == true || values.volumeIsEjectable == true
        guard MountedCard.isCardLike(removable: values.volumeIsRemovable, ejectable: values.volumeIsEjectable, isInternal: values.volumeIsInternal, network: network, browsable: values.volumeIsBrowsable) else { return nil }
        let name = values.volumeName ?? url.lastPathComponent
        // Some FAT/exFAT volumes do not publish a persistent UUID. The required
        // name+capacity fallback is weaker (two identical cards can collide).
        let identity = values.volumeUUIDString ?? "fallback:\(name):\(values.volumeTotalCapacity ?? 0)"
        return MountedCard(url: url, name: name, volumeUUID: identity, mediaLike: mediaLike)
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
        let keys: [URLResourceKey] = [.volumeIsRemovableKey, .volumeIsEjectableKey, .volumeIsInternalKey]
        guard let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: .skipHiddenVolumes) else { return }
        let paths = Set(urls.map(\.path))
        for path in Array(known.keys) where !paths.contains(path) {
            if let card = known.removeValue(forKey: path) { onUnmount?(card) }
        }
        for url in urls { checkMountedURL(url, forceRemount: false) }
    }
}
