// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "FootPedalOptionKey",
    platforms: [
        .macOS(.v12)
    ],
    targets: [
        .executableTarget(
            name: "FootPedalOptionKey",
            path: "sources/FootPedalOptionKey"
        )
    ]
)
