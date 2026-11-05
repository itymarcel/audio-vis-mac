// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "AudioWatch",
    platforms: [.macOS("14.2")],
    targets: [
        .executableTarget(name: "AudioWatch", path: "Sources/AudioWatch")
    ]
)
