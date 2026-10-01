// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PostureBuddy",
    platforms: [.macOS(.v14)],
    products: [.library(name: "PostureCore", targets: ["PostureCore"])],
    targets: [
        .target(name: "PostureCore", path: "Core"),
        .testTarget(name: "PostureCoreTests", dependencies: ["PostureCore"])
    ]
)
