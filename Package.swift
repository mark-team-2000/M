// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "M",
    platforms: [.macOS("15.0")], // PackageDescription 5.9 lacks .v15; deployment target is unchanged.
    products: [.executable(name: "M", targets: ["M"])],
    dependencies: [],
    targets: [
        .executableTarget(name: "M"),
        .testTarget(name: "MTests", dependencies: ["M"])
    ]
)
