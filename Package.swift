// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CodexAPIManager",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CodexAPIManager", targets: ["CodexAPIManager"])
    ],
    targets: [
        .executableTarget(
            name: "CodexAPIManager",
            exclude: ["App", "Views"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Security")
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)
