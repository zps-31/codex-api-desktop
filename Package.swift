// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CodexAPIManagerPlus",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CodexAPIManagerPlus", targets: ["CodexAPIManagerPlus"])
    ],
    targets: [
        .executableTarget(
            name: "CodexAPIManagerPlus",
            path: "Sources/CodexAPIManager",
            exclude: ["App", "Views"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("LocalAuthentication"),
                .linkedFramework("Network"),
                .linkedFramework("Security")
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)
