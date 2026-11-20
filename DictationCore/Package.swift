// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DictationCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "DictationCore", targets: ["DictationCore"])],
    targets: [
        .target(name: "DictationCore", resources: [.copy("Web")]),
        .testTarget(name: "DictationCoreTests", dependencies: ["DictationCore"]),
    ]
)
