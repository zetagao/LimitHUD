// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LimitHUD",
    platforms: [.macOS(.v13)],
    targets: [
        .systemLibrary(name: "CBridge", path: "Sources/CBridge"),
        .executableTarget(
            name: "LimitHUD",
            dependencies: ["CBridge"],
            path: "Sources/LimitHUD"
        )
    ],
    swiftLanguageVersions: [.v5]
)
