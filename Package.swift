// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "AudioViz",
    platforms: [.macOS("14.2")],
    targets: [
        .executableTarget(name: "AudioViz", path: "Sources/AudioViz")
    ]
)
