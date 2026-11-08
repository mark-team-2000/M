import Foundation
import Testing
@testable import M

@MainActor
struct CardLikeTests {
    @Test func cardLikeTruthTable() {
        // Classic removable/ejectable media qualifies regardless of the other flags.
        #expect(MountedCard.isCardLike(removable: true, ejectable: nil, isInternal: true, network: nil, browsable: nil))
        #expect(MountedCard.isCardLike(removable: false, ejectable: true, isInternal: true, network: true, browsable: false))
        // CFexpress Type B on NVMe readers: fixed, not ejectable, but external → qualifies (V2).
        #expect(MountedCard.isCardLike(removable: false, ejectable: false, isInternal: false, network: false, browsable: true))
        // Internal containers — boot volume included — never qualify.
        #expect(!MountedCard.isCardLike(removable: false, ejectable: false, isInternal: true, network: false, browsable: true))
        // Unknown internal state (nil) stays conservative: rejected.
        #expect(!MountedCard.isCardLike(removable: nil, ejectable: nil, isInternal: nil, network: nil, browsable: nil))
        // Network mounts and non-browsable system volumes are excluded.
        #expect(!MountedCard.isCardLike(removable: false, ejectable: false, isInternal: false, network: true, browsable: true))
        #expect(!MountedCard.isCardLike(removable: false, ejectable: false, isInternal: false, network: false, browsable: false))
    }

    @Test func externalFixedDiskShowsPanelOnlyWhenItHoldsMedia() async throws {
        let f = try Fixture()
        try f.put("plain/readme.txt")
        let repository = StoreRepository(url: f.root.appendingPathComponent("support/store.json"))
        let model = AppModel(repository: repository, systemEffects: false)
        let plain = MountedCard(url: f.root.appendingPathComponent("plain"), name: "SSD", volumeUUID: "ssd-uuid", mediaLike: false)
        model.didMount(plain)
        await model.waitForScan(plain.id)
        #expect(model.drafts.isEmpty) // External fixed disk without media: stays silent.
        try f.put("card/DCIM/a.JPG")
        let fixedCard = MountedCard(url: f.root.appendingPathComponent("card"), name: "CFe", volumeUUID: "cfe-uuid", mediaLike: false)
        model.didMount(fixedCard)
        await model.waitForScan(fixedCard.id)
        #expect(model.drafts.count == 1) // CFexpress-like: panel with media folders.
        #expect(model.drafts.first?.phase == .ready)
        // A removable card without media still shows its panel (classic behavior).
        try f.put("empty2/notes.txt")
        let classic = MountedCard(url: f.root.appendingPathComponent("empty2"), name: "SD", volumeUUID: "sd-uuid")
        model.didMount(classic)
        await model.waitForScan(classic.id)
        #expect(model.drafts.count == 2)
    }
}
