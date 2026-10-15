// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VisibleTab",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "VisibleTab", targets: ["VisibleTab"])],
    targets: [
        .target(name: "VisibleTabCore"),
        .executableTarget(name: "VisibleTab", dependencies: ["VisibleTabCore"]),
        .executableTarget(name: "VisibleTabChecks", dependencies: ["VisibleTabCore"], path: "Tests/VisibleTabCoreTests"),
        .executableTarget(name: "VisibleTabFixture", path: "Tests/VisibleTabFixture"),
    ],
    swiftLanguageModes: [.v5]
)
