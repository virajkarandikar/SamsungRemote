// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SamsungRemote",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "SamsungRemote", path: "Sources/SamsungRemote")
    ]
)
