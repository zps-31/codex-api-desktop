import Foundation

struct SessionUsageSnapshot: Equatable {
    let totalTokens: Int
    let lastRequestTokens: Int
    let contextWindow: Int?
}

final class SessionUsageMonitor {
    private struct FileSignature: Equatable {
        let modifiedAt: Date
        let size: Int
        let fileID: UInt64
    }

    private var rootPath: String?
    private var latestFile: URL?
    private var latestSignature: FileSignature?
    private var snapshot: SessionUsageSnapshot?
    private var lastDiscovery = Date.distantPast

    func latest(in sessionsDirectory: URL) -> SessionUsageSnapshot? {
        let now = Date()
        let rootChanged = rootPath != sessionsDirectory.path
        let needsDiscovery = rootChanged
            || latestFile == nil
            || now.timeIntervalSince(lastDiscovery) >= 10

        if needsDiscovery {
            let previousFile = latestFile
            rootPath = sessionsDirectory.path
            latestFile = SessionUsageService.latestSessionFile(
                in: sessionsDirectory
            )
            lastDiscovery = now
            if latestFile != previousFile {
                latestSignature = nil
                snapshot = nil
            }
        }

        guard let latestFile,
              let signature = Self.signature(for: latestFile) else {
            return nil
        }
        if signature == latestSignature {
            return snapshot
        }
        latestSignature = signature
        if let refreshed = SessionUsageService.snapshot(from: latestFile) {
            snapshot = refreshed
        }
        return snapshot
    }

    func invalidate() {
        lastDiscovery = .distantPast
        latestSignature = nil
    }

    private static func signature(for url: URL) -> FileSignature? {
        guard let attributes = try? FileManager.default.attributesOfItem(
            atPath: url.path
        ) else {
            return nil
        }
        return FileSignature(
            modifiedAt: attributes[.modificationDate] as? Date ?? .distantPast,
            size: (attributes[.size] as? NSNumber)?.intValue ?? 0,
            fileID: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
        )
    }
}

enum SessionUsageService {
    static func latest(in sessionsDirectory: URL) -> SessionUsageSnapshot? {
        guard let latestFile = latestSessionFile(in: sessionsDirectory) else {
            return nil
        }
        return snapshot(from: latestFile)
    }

    static func latestSessionFile(in sessionsDirectory: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: sessionsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var latestFile: (url: URL, date: Date)?
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let date = values.contentModificationDate else { continue }
            if latestFile == nil || date > latestFile!.date { latestFile = (url, date) }
        }
        return latestFile?.url
    }

    static func snapshot(from url: URL) -> SessionUsageSnapshot? {
        guard let file = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? file.close() }

        let end = (try? file.seekToEnd()) ?? 0
        let limit: UInt64 = 4 * 1_024 * 1_024
        try? file.seek(toOffset: end > limit ? end - limit : 0)
        guard let data = try? file.readToEnd(),
              let text = String(data: data, encoding: .utf8) else { return nil }

        for line in text.split(whereSeparator: { $0.isNewline }).reversed() where line.contains("\"token_count\"") {
            guard let root = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let payload = root["payload"] as? [String: Any],
                  payload["type"] as? String == "token_count",
                  let info = payload["info"] as? [String: Any],
                  let total = tokenTotal(info["total_token_usage"] ?? info["totalTokenUsage"]),
                  let recent = tokenTotal(info["last_token_usage"] ?? info["lastTokenUsage"]) else { continue }
            let context = integer(info["model_context_window"] ?? info["modelContextWindow"])
            return SessionUsageSnapshot(totalTokens: total, lastRequestTokens: recent, contextWindow: context)
        }
        return nil
    }

    private static func tokenTotal(_ value: Any?) -> Int? {
        guard let usage = value as? [String: Any] else { return nil }
        return integer(usage["total_tokens"] ?? usage["totalTokens"])
    }

    private static func integer(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }
}
