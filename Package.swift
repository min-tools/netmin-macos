// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Netmin",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "NetminApp",
            path: "Sources/NetminApp",
            resources: [.process("Resources")],
            swiftSettings: [.define("NETMIN_SWIFTPM")]
        )
    ]
)
