// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LucidCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "LucidCore", targets: ["LucidCore"]),
    ],
    targets: [
        .target(name: "LucidCore"),
        .testTarget(name: "LucidCoreTests", dependencies: ["LucidCore"]),
    ]
)
