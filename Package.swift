// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TibidleMultiManager",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "TibidleCore"),
        .executableTarget(name: "TibidleMultiManager", dependencies: ["TibidleCore"]),
        .testTarget(name: "TibidleCoreTests", dependencies: ["TibidleCore"]),
    ]
)
