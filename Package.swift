// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Layouts",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Layouts",
            path: "Sources/Layouts"
        )
    ]
)
