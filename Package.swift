// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LevelMap",
    platforms: [
        .iOS(.v18),
        .macOS(.v14),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "LevelMap", targets: ["LevelMap"]),
        // A debug tool for designing routes. Keep it out of release builds.
        .library(name: "LevelMapEditor", targets: ["LevelMapEditor"]),
    ],
    targets: [
        .target(name: "LevelMap"),
        .target(name: "LevelMapEditor", dependencies: ["LevelMap"]),
        .testTarget(name: "LevelMapTests", dependencies: ["LevelMap"]),
        .testTarget(name: "LevelMapEditorTests", dependencies: ["LevelMapEditor", "LevelMap"]),
    ]
)
