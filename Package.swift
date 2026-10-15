// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClearCommandTab",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ClearCommandTab", targets: ["ClearCommandTab"])],
    targets: [
        .target(name: "ClearCommandTabCore"),
        .executableTarget(name: "ClearCommandTab", dependencies: ["ClearCommandTabCore"]),
        .executableTarget(name: "ClearCommandTabChecks", dependencies: ["ClearCommandTabCore"], path: "Tests/ClearCommandTabCoreTests"),
        .executableTarget(name: "ClearCommandTabFixture", path: "Tests/ClearCommandTabFixture"),
    ],
    swiftLanguageModes: [.v5]
)
