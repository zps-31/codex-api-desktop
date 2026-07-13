import Foundation

enum WorkspacePathResolver {
    static func defaultWorkingDirectory(
        home: URL? = nil,
        fileManager: FileManager = .default
    ) -> String {
        let resolvedHome = home ?? fileManager.homeDirectoryForCurrentUser
        let candidates = [
            resolvedHome.appendingPathComponent("Documents/Codex", isDirectory: true),
            resolvedHome.appendingPathComponent("Documents", isDirectory: true),
            resolvedHome
        ]
        return candidates.first {
            isDirectory($0, fileManager: fileManager)
        }?.standardizedFileURL.path ?? resolvedHome.standardizedFileURL.path
    }

    static func resolve(
        _ path: String?,
        home: URL? = nil,
        fileManager: FileManager = .default
    ) -> String {
        let resolvedHome = home ?? fileManager.homeDirectoryForCurrentUser
        guard let path,
              !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return defaultWorkingDirectory(home: resolvedHome, fileManager: fileManager)
        }

        let expanded = NSString(string: path).expandingTildeInPath
        let original = URL(fileURLWithPath: expanded, isDirectory: true)
            .standardizedFileURL
        if isDirectory(original, fileManager: fileManager) {
            return original.path
        }

        let components = original.pathComponents
        if components.count >= 4,
           components[0] == "/",
           components[1] == "Users" {
            let rebased = components.dropFirst(3).reduce(resolvedHome) {
                $0.appendingPathComponent($1)
            }
            if isDirectory(rebased, fileManager: fileManager) {
                return rebased.standardizedFileURL.path
            }
            return defaultWorkingDirectory(home: resolvedHome, fileManager: fileManager)
        }

        return original.path
    }

    private static func isDirectory(
        _ url: URL,
        fileManager: FileManager
    ) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }
}
