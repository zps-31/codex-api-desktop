import Foundation

struct SessionUsageSnapshot: Equatable {
    let totalTokens: Int
    let lastRequestTokens: Int
    let contextWindow: Int?
}

enum SessionUsageService {
    static func latest(in sessionsDirectory: URL) -> SessionUsageSnapshot? {
        guard let enumerator = FileManager.default.enumerator(
            at: sessionsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var latestFile: (url: URL, date: Date)?
        var inspected = 0
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            inspected += 1
            if inspected > 5_000 { break }
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let date = values.contentModificationDate else { continue }
            if latestFile == nil || date > latestFile!.date { latestFile = (url, date) }
        }
        guard let url = latestFile?.url,
              let file = try? FileHandle(forReadingFrom: url) else { return nil }
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
