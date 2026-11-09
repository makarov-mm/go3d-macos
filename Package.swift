// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Go3D",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Go3D", path: "Sources/Go3D"),
    ]
)
