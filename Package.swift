// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HeartBar",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "HeartBar", targets: ["HeartBarApp"])],
    targets: [
        .target(name: "HeartBarCore"),
        .executableTarget(name: "HeartBarApp", dependencies: ["HeartBarCore"]),
        .testTarget(name: "HeartBarCoreTests", dependencies: ["HeartBarCore"])
    ],
    swiftLanguageModes: [.v6]
)
