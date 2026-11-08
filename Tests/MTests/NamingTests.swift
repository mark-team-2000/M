import Foundation
import Testing
@testable import M

struct NamingTests {
    @Test func sanitizesAndAllocatesCollisionSuffixes() throws {
        let f = try Fixture()
        #expect(FolderNaming.sanitize(" a/b:c*?\"<>|\n ", volumeName: "SD") == "a_b_c______")
        #expect(FolderNaming.sanitize(" \n ", volumeName: "EOS_DIGITAL") == "EOS_DIGITAL")
        #expect(FolderNaming.sanitize("..", volumeName: "") == "SCHEDE")
        #expect(FolderNaming.sanitize(String(repeating: "è", count: 100), volumeName: "SD").count == 80)
        let first = try FolderNaming.reserve(in: f.root, name: "Tessera")
        let second = try FolderNaming.reserve(in: f.root, name: "Tessera")
        #expect(first.lastPathComponent == "Tessera")
        #expect(second.lastPathComponent == "Tessera 2")
        let long = String(repeating: "x", count: 80)
        _ = try FolderNaming.reserve(in: f.root, name: long)
        let longCollision = try FolderNaming.reserve(in: f.root, name: long)
        #expect(longCollision.lastPathComponent.count == 80)
        #expect(longCollision.lastPathComponent.hasSuffix(" 2"))
    }
}
