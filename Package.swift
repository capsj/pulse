// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Pulse",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Pulse", path: "Sources/Pulse")
    ]
)
