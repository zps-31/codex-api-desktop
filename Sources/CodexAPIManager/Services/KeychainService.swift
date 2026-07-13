import Darwin
import Foundation
import LocalAuthentication
import Security

struct KeychainService {
    static let service = "com.zps.codex-api-manager-plus.api-keys"
    static let legacyServices = ["com.zps.codex-api-manager.api-keys"]

    private let keychainPath: String?

    init(fileManager: FileManager = .default) {
        Self.normalizeProcessHome(fileManager: fileManager)
        keychainPath = Self.prepareLoginKeychain(fileManager: fileManager)
    }

    @discardableResult
    static func normalizeProcessHome(
        fileManager: FileManager = .default
    ) -> URL {
        let accountDirectory = getpwuid(getuid()).flatMap { record in
            record.pointee.pw_dir.map { String(cString: $0) }
        }
        let home = resolvedUserHome(
            accountDirectory: accountDirectory,
            fallback: fileManager.homeDirectoryForCurrentUser
        )
        setenv("HOME", home.path, 1)
        setenv("CFFIXED_USER_HOME", home.path, 1)
        return home
    }

    func save(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let query = query(service: Self.service, account: account)
        var insert = query
        insert[kSecValueData as String] = data
        let addStatus = SecItemAdd(insert as CFDictionary, nil)

        if addStatus == errSecDuplicateItem {
            let updateStatus = SecItemUpdate(
                query as CFDictionary,
                [kSecValueData as String: data] as CFDictionary
            )
            guard updateStatus == errSecSuccess else {
                throw KeychainError.status(updateStatus)
            }
        } else if addStatus != errSecSuccess {
            throw KeychainError.status(addStatus)
        }
    }

    func contains(account: String) -> Bool {
        Self.allServices.contains { service in
            var lookup = query(service: service, account: account)
            lookup[kSecReturnData as String] = false
            let context = LAContext()
            context.interactionNotAllowed = true
            lookup[kSecUseAuthenticationContext as String] = context
            return SecItemCopyMatching(
                lookup as CFDictionary,
                nil
            ) == errSecSuccess
        }
    }

    func read(account: String) throws -> String? {
        for service in Self.allServices {
            if let value = try read(service: service, account: account) {
                if service != Self.service {
                    try? save(value, account: account)
                }
                return value
            }
        }
        return nil
    }

    private func read(service: String, account: String) throws -> String? {
        var lookup = query(service: service, account: account)
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        let context = LAContext()
        context.interactionNotAllowed = true
        lookup[kSecUseAuthenticationContext as String] = context
        var item: CFTypeRef?
        let status = SecItemCopyMatching(
            lookup as CFDictionary,
            &item
        )
        if status == errSecSuccess {
            guard let data = item as? Data,
                  let value = String(data: data, encoding: .utf8),
                  !value.isEmpty else {
                throw KeychainError.invalidData
            }
            return value
        }
        if status == errSecItemNotFound { return nil }
        guard status == errSecInteractionNotAllowed
                || status == errSecAuthFailed else {
            throw KeychainError.status(status)
        }

        // Apple's signed helper remains stable across local ad-hoc app rebuilds.
        let output = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = [
            "find-generic-password",
            "-s", service,
            "-a", account,
            "-w"
        ]
        if let keychainPath {
            process.arguments?.append(keychainPath)
        }
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        if process.terminationStatus == 44 { return nil }
        guard process.terminationStatus == 0 else {
            throw KeychainError.command(
                operation: "读取",
                status: process.terminationStatus
            )
        }
        guard let value = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .newlines),
              !value.isEmpty else {
            throw KeychainError.invalidData
        }
        return value
    }

    func delete(account: String) throws {
        for service in Self.allServices {
            var deletion = query(service: service, account: account)
            let context = LAContext()
            context.interactionNotAllowed = true
            deletion[kSecUseAuthenticationContext as String] = context
            let status = SecItemDelete(deletion as CFDictionary)
            if status == errSecSuccess || status == errSecItemNotFound {
                continue
            }
            guard status == errSecInteractionNotAllowed
                    || status == errSecAuthFailed else {
                throw KeychainError.status(status)
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
            process.arguments = [
                "delete-generic-password",
                "-s", service,
                "-a", account
            ]
            if let keychainPath {
                process.arguments?.append(keychainPath)
            }
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0
                    || process.terminationStatus == 44 else {
                throw KeychainError.command(
                    operation: "删除",
                    status: process.terminationStatus
                )
            }
        }
    }

    func verifyRoundTrip() throws {
        let account = "diagnostic-\(UUID().uuidString)"
        let initialValue = "codex-api-plus-keychain-diagnostic"
        let updatedValue = "\(initialValue)-updated"
        var needsCleanup = false
        defer {
            if needsCleanup {
                try? delete(account: account)
            }
        }
        try save(initialValue, account: account)
        needsCleanup = true
        guard contains(account: account),
              try read(account: account) == initialValue else {
            throw KeychainError.invalidData
        }
        try save(updatedValue, account: account)
        guard try read(account: account) == updatedValue else {
            throw KeychainError.invalidData
        }
        try delete(account: account)
        needsCleanup = false
        guard !contains(account: account) else {
            throw KeychainError.invalidData
        }
    }

    private func query(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    static func resolvedUserHome(
        accountDirectory: String?,
        fallback: URL
    ) -> URL {
        guard let accountDirectory,
              !accountDirectory.trimmingCharacters(
                  in: .whitespacesAndNewlines
              ).isEmpty else {
            return fallback.standardizedFileURL
        }
        return URL(
            fileURLWithPath: accountDirectory,
            isDirectory: true
        ).standardizedFileURL
    }

    static func loginKeychainURL(home: URL) -> URL {
        home.appendingPathComponent(
            "Library/Keychains/login.keychain-db",
            isDirectory: false
        )
    }

    private static var allServices: [String] {
        [service] + legacyServices
    }

    static func parseKeychainList(_ output: String) -> [String] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let path = line.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            return path.isEmpty ? nil : path
        }
    }

    private static func prepareLoginKeychain(
        fileManager: FileManager
    ) -> String? {
        let home = normalizeProcessHome(fileManager: fileManager)
        let loginKeychain = loginKeychainURL(home: home)
        guard fileManager.fileExists(atPath: loginKeychain.path) else {
            return nil
        }

        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = home.path
        environment["CFFIXED_USER_HOME"] = home.path

        let defaultResult = runSecurity(
            arguments: ["default-keychain", "-d", "user"],
            environment: environment
        )
        if defaultResult.status != 0 {
            _ = runSecurity(
                arguments: [
                    "default-keychain", "-d", "user", "-s",
                    loginKeychain.path
                ],
                environment: environment
            )
        }

        let listResult = runSecurity(
            arguments: ["list-keychains", "-d", "user"],
            environment: environment
        )
        var paths = parseKeychainList(listResult.output)
        if !paths.contains(loginKeychain.path) {
            paths.append(loginKeychain.path)
            _ = runSecurity(
                arguments: [
                    "list-keychains", "-d", "user", "-s"
                ] + paths,
                environment: environment
            )
        }
        return loginKeychain.path
    }

    private static func runSecurity(
        arguments: [String],
        environment: [String: String]
    ) -> (status: Int32, output: String) {
        let output = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = arguments
        process.environment = environment
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return (-1, "")
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (
            process.terminationStatus,
            String(data: data, encoding: .utf8) ?? ""
        )
    }
}

enum KeychainError: LocalizedError {
    case status(OSStatus)
    case invalidData
    case command(operation: String, status: Int32)

    var errorDescription: String? {
        switch self {
        case .status(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "未知错误"
            if status == errSecNoDefaultKeychain {
                return "钥匙串操作失败：找不到登录钥匙串（\(status)）。"
            }
            return "钥匙串操作失败：\(message)（\(status)）"
        case .invalidData:
            return "钥匙串中的 API Key 数据无法读取。"
        case .command(let operation, let status):
            return "无法通过 macOS 钥匙串\(operation) API Key（状态 \(status)）。"
        }
    }
}
