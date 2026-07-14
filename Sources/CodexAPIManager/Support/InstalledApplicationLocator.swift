import AppKit
import Darwin
import Foundation

enum InstalledApplicationLocator {
    private static let apiCodexBundleIDs = ["com.zps.codex-api-plus"]
    private static let apiCodexNames = ["Codex API Plus.app"]
    private static let officialCodexBundleIDs = ["com.openai.codex"]
    private static let officialCodexNames = [
        "ChatGPT.app",
        "Codex.app",
        "Codex Office.app"
    ]

    static func apiCodexApplicationURL() -> URL? {
        applicationURL(
            bundleIdentifiers: apiCodexBundleIDs,
            names: apiCodexNames
        )
    }

    static func officialCodexApplicationURL() -> URL? {
        applicationURL(
            bundleIdentifiers: officialCodexBundleIDs,
            names: officialCodexNames
        )
    }

    static func meterApplicationURL() -> URL? {
        applicationURL(
            bundleIdentifiers: ["com.codexmeter.macos.plus"],
            names: ["Codex Meter Plus.app"]
        )
    }

    static func chatGPTClassicApplicationURL() -> URL? {
        applicationURL(
            bundleIdentifiers: ["com.openai.chat"],
            names: ["ChatGPT Classic.app"]
        )
    }

    static func codexCLIURL() -> URL? {
        for application in [
            applicationURL(
                bundleIdentifiers: apiCodexBundleIDs,
                names: apiCodexNames
            ),
            officialCodexApplicationURL()
        ].compactMap({ $0 }) {
            let candidate = application
                .appendingPathComponent("Contents/Resources", isDirectory: true)
                .appendingPathComponent("codex")
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        let home = FileManager.default.homeDirectoryForCurrentUser
        var paths = [
            home.appendingPathComponent(".local/bin/codex").path,
            home.appendingPathComponent(".npm-global/bin/codex").path,
            home.appendingPathComponent(".bun/bin/codex").path,
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/usr/bin/codex"
        ]
        if let environmentPath = ProcessInfo.processInfo.environment["PATH"] {
            paths.append(contentsOf: environmentPath.split(separator: ":").map {
                URL(fileURLWithPath: String($0), isDirectory: true)
                    .appendingPathComponent("codex")
                    .path
            })
        }
        var seen: Set<String> = []
        return paths.lazy
            .filter { seen.insert($0).inserted }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    static func applicationURL(
        bundleIdentifiers: [String],
        names: [String],
        additionalDirectories: [URL] = []
    ) -> URL? {
        let fileManager = FileManager.default
        var candidates: [URL] = []
        let siblingDirectory = Bundle.main.bundleURL.deletingLastPathComponent()
        let directories = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications", isDirectory: true),
            siblingDirectory
        ] + additionalDirectories

        for directory in directories {
            candidates.append(contentsOf: names.map {
                directory.appendingPathComponent($0, isDirectory: true)
            })
        }
        for identifier in bundleIdentifiers {
            if let located = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: identifier
            ) {
                candidates.append(located)
            }
        }

        var seen: Set<String> = []
        return candidates.lazy
            .map { $0.standardizedFileURL.resolvingSymlinksInPath() }
            .filter { seen.insert($0.path).inserted }
            .first {
                isValidApplication(
                    at: $0,
                    acceptedBundleIdentifiers: bundleIdentifiers
                )
            }
    }

    static func isValidApplication(
        at url: URL,
        acceptedBundleIdentifiers: [String]
    ) -> Bool {
        var isDirectory: ObjCBool = false
        guard url.pathExtension.lowercased() == "app",
              FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              let bundle = Bundle(url: url),
              let executable = bundle.executableURL,
              FileManager.default.isExecutableFile(atPath: executable.path),
              supportsExecutableArchitectures(
                  bundle.executableArchitectures,
                  hostArchitectures: hostExecutableArchitectures
              ) else {
            return false
        }
        return acceptedBundleIdentifiers.isEmpty
            || bundle.bundleIdentifier.map(acceptedBundleIdentifiers.contains) == true
    }

    static func supportsExecutableArchitectures(
        _ executableArchitectures: [NSNumber]?,
        hostArchitectures: Set<Int>
    ) -> Bool {
        guard let executableArchitectures, !executableArchitectures.isEmpty else {
            return true
        }
        return executableArchitectures.contains {
            hostArchitectures.contains($0.intValue)
        }
    }

    private static var hostExecutableArchitectures: Set<Int> {
#if arch(arm64)
        return [NSBundleExecutableArchitectureARM64]
#elseif arch(x86_64)
        if isRunningUnderRosetta {
            return [
                NSBundleExecutableArchitectureARM64,
                NSBundleExecutableArchitectureX86_64
            ]
        }
        return [NSBundleExecutableArchitectureX86_64]
#else
        return []
#endif
    }

#if arch(x86_64)
    private static var isRunningUnderRosetta: Bool {
        var translated: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname(
            "sysctl.proc_translated",
            &translated,
            &size,
            nil,
            0
        ) == 0 && translated == 1
    }
#endif
}
