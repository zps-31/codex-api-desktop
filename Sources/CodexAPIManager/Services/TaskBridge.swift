import Foundation
import Darwin

struct TaskBridgeRecord: Codable, Equatable {
    let schemaVersion: Int
    let taskID: UUID
    let projectName: String
    let profileName: String
    let providerName: String
    let model: String
    let scenario: String
    let startedAt: Date
    let billingProvider: String?
    let taskBudgetUSD: Double?
    let endedAt: Date?
    let status: String?
    let processID: Int32?
    let workingDirectory: String?
    let profileID: UUID?

    func ending(at date: Date, status: String) -> TaskBridgeRecord {
        TaskBridgeRecord(
            schemaVersion: max(schemaVersion, 3),
            taskID: taskID,
            projectName: projectName,
            profileName: profileName,
            providerName: providerName,
            model: model,
            scenario: scenario,
            startedAt: startedAt,
            billingProvider: billingProvider,
            taskBudgetUSD: taskBudgetUSD,
            endedAt: date,
            status: status,
            processID: processID,
            workingDirectory: workingDirectory,
            profileID: profileID
        )
    }

    func updating(profile: ProviderProfile) -> TaskBridgeRecord {
        TaskBridgeRecord(
            schemaVersion: max(schemaVersion, 4),
            taskID: taskID,
            projectName: projectName,
            profileName: profile.name,
            providerName: profile.preset.title,
            model: profile.model,
            scenario: profile.workScenario.title,
            startedAt: startedAt,
            billingProvider: TaskBridge.billingProvider(for: profile),
            taskBudgetUSD: profile.taskBudgetUSD > 0 ? profile.taskBudgetUSD : nil,
            endedAt: endedAt,
            status: status,
            processID: processID,
            workingDirectory: workingDirectory,
            profileID: profile.id
        )
    }
}

struct TaskBridge {
    private static let maximumBridgeFileSize = 2 * 1_024 * 1_024
    static let directoryName = "Codex API Manager Plus/task-bridge"
    static let activeTaskFilename = "active-task.json"
    static let historyFilename = "task-history.json"

    static func defaultDirectory(fileManager: FileManager = .default) throws -> URL {
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return support.appendingPathComponent(directoryName, isDirectory: true)
    }

    static func writeStartedTask(
        profile: ProviderProfile,
        workingDirectory: String,
        processID: Int32,
        fileManager: FileManager = .default
    ) throws -> TaskBridgeRecord {
        let directory = try defaultDirectory(fileManager: fileManager)
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let projectName = URL(fileURLWithPath: workingDirectory, isDirectory: true)
            .lastPathComponent
        var history = readHistory(fileManager: fileManager)
        if let previous = readActiveTask(fileManager: fileManager) {
            let finished = previous.ending(at: Date(), status: "replaced")
            history.removeAll { $0.taskID == previous.taskID }
            history.insert(finished, at: 0)
        }

        let record = TaskBridgeRecord(
            schemaVersion: 4,
            taskID: UUID(),
            projectName: projectName.isEmpty ? "未命名项目" : projectName,
            profileName: profile.name,
            providerName: profile.preset.title,
            model: profile.model,
            scenario: profile.workScenario.title,
            startedAt: Date(),
            billingProvider: billingProvider(for: profile),
            taskBudgetUSD: profile.taskBudgetUSD > 0 ? profile.taskBudgetUSD : nil,
            endedAt: nil,
            status: "running",
            processID: processID,
            workingDirectory: workingDirectory,
            profileID: profile.id
        )
        let data = try JSONEncoder.taskBridge.encode(record)
        let file = directory.appendingPathComponent(activeTaskFilename)
        try data.write(to: file, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        history.removeAll { $0.taskID == record.taskID }
        history.insert(record, at: 0)
        try writeHistory(Array(history.prefix(100)), directory: directory, fileManager: fileManager)
        return record
    }

    static func updateActiveTask(
        profile: ProviderProfile,
        fileManager: FileManager = .default
    ) throws {
        let directory = try defaultDirectory(fileManager: fileManager)
        guard let active = readActiveTask(in: directory), isRunning(active) else { return }
        let updated = active.updating(profile: profile)
        let file = directory.appendingPathComponent(activeTaskFilename)
        try JSONEncoder.taskBridge.encode(updated).write(to: file, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        var history = readHistory(in: directory)
        history.removeAll { $0.taskID == updated.taskID }
        history.insert(updated, at: 0)
        try writeHistory(Array(history.prefix(100)), directory: directory, fileManager: fileManager)
    }

    static func readHistory(fileManager: FileManager = .default) -> [TaskBridgeRecord] {
        guard let directory = try? defaultDirectory(fileManager: fileManager) else {
            return []
        }
        return readHistory(in: directory)
    }

    static func readHistory(in directory: URL) -> [TaskBridgeRecord] {
        guard let data = boundedData(at: directory.appendingPathComponent(historyFilename)) else { return [] }
        return Array(((try? JSONDecoder.taskBridge.decode([TaskBridgeRecord].self, from: data)) ?? []).prefix(100))
    }

    static func reconcileHistory(
        fileManager: FileManager = .default,
        now: Date = Date()
    ) -> [TaskBridgeRecord] {
        guard let directory = try? defaultDirectory(fileManager: fileManager) else {
            return []
        }
        return reconcileHistory(in: directory, fileManager: fileManager, now: now)
    }

    static func reconcileHistory(
        in directory: URL,
        fileManager: FileManager = .default,
        now: Date = Date()
    ) -> [TaskBridgeRecord] {
        var history = readHistory(in: directory)
        guard let active = readActiveTask(in: directory) else {
            return history
        }

        if isRunning(active) {
            if !history.contains(where: { $0.taskID == active.taskID }) {
                history.insert(active, at: 0)
            }
            return history
        }

        let finished = active.ending(at: now, status: "finished")
        history.removeAll { $0.taskID == active.taskID }
        history.insert(finished, at: 0)
        try? writeHistory(
            Array(history.prefix(100)),
            directory: directory,
            fileManager: fileManager
        )
        try? fileManager.removeItem(
            at: directory.appendingPathComponent(activeTaskFilename)
        )
        return history
    }

    static func isRunning(_ record: TaskBridgeRecord) -> Bool {
        guard record.endedAt == nil, record.status != "replaced" else { return false }
        guard let processID = record.processID, processID > 0 else { return false }
        return kill(processID, 0) == 0 || errno == EPERM
    }

    private static func readActiveTask(fileManager: FileManager) -> TaskBridgeRecord? {
        guard let directory = try? defaultDirectory(fileManager: fileManager) else {
            return nil
        }
        return readActiveTask(in: directory)
    }

    private static func readActiveTask(in directory: URL) -> TaskBridgeRecord? {
        guard let data = boundedData(at: directory.appendingPathComponent(activeTaskFilename)) else { return nil }
        return try? JSONDecoder.taskBridge.decode(TaskBridgeRecord.self, from: data)
    }

    private static func boundedData(at url: URL) -> Data? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size >= 0, size <= maximumBridgeFileSize else { return nil }
        return try? Data(contentsOf: url, options: .mappedIfSafe)
    }

    private static func writeHistory(
        _ records: [TaskBridgeRecord],
        directory: URL,
        fileManager: FileManager
    ) throws {
        let file = directory.appendingPathComponent(historyFilename)
        try JSONEncoder.taskBridge.encode(records).write(to: file, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    static func billingProvider(for profile: ProviderProfile) -> String? {
        let baseURL = profile.baseURL.lowercased()
        if baseURL.contains("micuapi.ai") { return "micu" }
        if baseURL.contains("cctq.ai") { return "cctq" }
        guard let components = URLComponents(string: profile.baseURL),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased() else { return nil }
        var origin = "\(scheme)://\(host)"
        if let port = components.port { origin += ":\(port)" }
        return "origin:\(origin)"
    }
}

private extension JSONDecoder {
    static let taskBridge: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

private extension JSONEncoder {
    static let taskBridge: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}
