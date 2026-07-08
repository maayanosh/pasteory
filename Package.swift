// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "PasteClone",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ClapCore"),
        .target(name: "PasteCloneKit", dependencies: ["ClapCore"]),
        .executableTarget(name: "PasteClone", dependencies: ["PasteCloneKit"]),
        .testTarget(name: "ClapCoreTests", dependencies: ["ClapCore"]),
        .testTarget(name: "PasteCloneKitTests", dependencies: ["PasteCloneKit"]),
    ],
    swiftLanguageVersions: [.v5]
)
