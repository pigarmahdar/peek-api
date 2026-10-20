import Foundation

public final class KeyResolver: @unchecked Sendable {
    public static let shared = KeyResolver()

    private let lock = NSLock()
    private var cachedKey: String?

    public init() {}

    public func resolveKey() -> String? {
        lock.lock()
        defer { lock.unlock() }

        if let cached = cachedKey, !cached.isEmpty {
            return cached
        }

        // 1. Environment variable
        if let envKey = ProcessInfo.processInfo.environment["OPENROUTER_MANAGEMENT_KEY"],
           !envKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let key = envKey.trimmingCharacters(in: .whitespacesAndNewlines)
            cachedKey = key
            return key
        }

        // 2. Local .env file in current working directory
        if let dotEnvKey = resolveFromDotEnv() {
            cachedKey = dotEnvKey
            return dotEnvKey
        }

        // 3. Custom Key Command from environment (e.g., OPENROUTER_KEY_COMMAND="bw get password openrouter-management")
        if let envCmd = ProcessInfo.processInfo.environment["OPENROUTER_KEY_COMMAND"],
           !envCmd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let cmdKey = executeKeyCommand(envCmd) {
                cachedKey = cmdKey
                return cmdKey
            }
        }

        // 4. XDG Config file (~/.config/peek-api/config.json or ~/.peek-api/config.json)
        if let configKey = resolveFromConfigFile() {
            cachedKey = configKey
            return configKey
        }

        return nil
    }

    public func invalidateCache() {
        lock.lock()
        defer { lock.unlock() }
        cachedKey = nil
    }

    public func saveKey(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let fileManager = FileManager.default
        let configDir = fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".config/peek-api")
        let configFile = configDir.appendingPathComponent("config.json")
        do {
            try fileManager.createDirectory(at: configDir, withIntermediateDirectories: true)
            let json = """
            {
              "key": "\(trimmed)"
            }
            """
            try json.write(to: configFile, atomically: true, encoding: .utf8)
            invalidateCache()
            cachedKey = trimmed
            return true
        } catch {
            return false
        }
    }

    // MARK: - .env File Resolver

    public func resolveFromDotEnv(directory: String = FileManager.default.currentDirectoryPath) -> String? {
        let fileManager = FileManager.default
        let envURL = URL(fileURLWithPath: directory).appendingPathComponent(".env")

        guard fileManager.fileExists(atPath: envURL.path),
              let content = try? String(contentsOf: envURL, encoding: .utf8) else {
            return nil
        }

        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") || trimmed.isEmpty { continue }

            let parts = trimmed.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                let name = parts[0].trimmingCharacters(in: .whitespaces)
                var val = parts[1].trimmingCharacters(in: .whitespaces)
                if (val.hasPrefix("\"") && val.hasSuffix("\"")) || (val.hasPrefix("'") && val.hasSuffix("'")) {
                    val = String(val.dropFirst().dropLast())
                }
                if name == "OPENROUTER_MANAGEMENT_KEY" || name == "OPENROUTER_KEY" {
                    let cleaned = val.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cleaned.isEmpty {
                        return cleaned
                    }
                }
            }
        }

        return nil
    }

    // MARK: - Config File Resolver

    public struct PeekConfigFile: Codable {
        public let key: String?
        public let keyCommand: String?

        enum CodingKeys: String, CodingKey {
            case key
            case keyCommand = "key_command"
        }
    }

    private func resolveFromConfigFile() -> String? {
        let fileManager = FileManager.default
        let homeDir = fileManager.homeDirectoryForCurrentUser

        let candidatePaths = [
            homeDir.appendingPathComponent(".config/peek-api/config.json"),
            homeDir.appendingPathComponent(".peek-api/config.json")
        ]

        for url in candidatePaths {
            guard fileManager.fileExists(atPath: url.path),
                  let data = try? Data(contentsOf: url),
                  let config = try? JSONDecoder().decode(PeekConfigFile.self, from: data) else {
                continue
            }

            if let staticKey = config.key?.trimmingCharacters(in: .whitespacesAndNewlines), !staticKey.isEmpty {
                return staticKey
            }

            if let cmd = config.keyCommand?.trimmingCharacters(in: .whitespacesAndNewlines), !cmd.isEmpty {
                if let output = executeKeyCommand(cmd) {
                    return output
                }
            }
        }

        return nil
    }

    // MARK: - Command Runner (e.g. Bitwarden CLI)

    public func executeKeyCommand(_ command: String) -> String? {
        let process = Process()
        let pipe = Pipe()
        let errorPipe = Pipe()

        process.standardOutput = pipe
        process.standardError = errorPipe
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]

        do {
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                return nil
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (output?.isEmpty == false) ? output : nil
        } catch {
            return nil
        }
    }
}
