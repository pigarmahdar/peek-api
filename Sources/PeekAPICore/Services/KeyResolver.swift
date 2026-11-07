import Foundation

public final class KeyResolver: @unchecked Sendable {
    public static let shared = KeyResolver()

    private let lock = NSLock()
    private var cachedKey: String?
    private let customConfigURL: URL?

    public init(configFileURL: URL? = nil) {
        self.customConfigURL = configFileURL
    }

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

        let success = updateConfigFile { config in
            config.key = trimmed
        }
        if success {
            lock.lock()
            cachedKey = trimmed
            lock.unlock()
        }
        return success
    }

    public func resolveBudgetTarget() -> Double? {
        loadConfigFile()?.monthlyBudgetTarget
    }

    public func saveBudgetTarget(_ budget: Double) -> Bool {
        guard budget > 0 else { return false }
        return updateConfigFile { config in
            config.monthlyBudgetTarget = budget
        }
    }

    public func resolveSpikeguardThreshold() -> Double? {
        loadConfigFile()?.spikeguardThreshold
    }

    public func saveSpikeguardThreshold(_ threshold: Double) -> Bool {
        guard threshold > 0 else { return false }
        return updateConfigFile { config in
            config.spikeguardThreshold = threshold
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
        public var key: String?
        public var keyCommand: String?
        public var monthlyBudgetTarget: Double?
        public var spikeguardThreshold: Double?

        public init(key: String? = nil, keyCommand: String? = nil, monthlyBudgetTarget: Double? = nil, spikeguardThreshold: Double? = nil) {
            self.key = key
            self.keyCommand = keyCommand
            self.monthlyBudgetTarget = monthlyBudgetTarget
            self.spikeguardThreshold = spikeguardThreshold
        }

        enum CodingKeys: String, CodingKey {
            case key
            case keyCommand = "key_command"
            case monthlyBudgetTarget = "monthly_budget_target"
            case spikeguardThreshold = "spikeguard_threshold"
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.key = try container.decodeIfPresent(String.self, forKey: .key)
            self.keyCommand = try container.decodeIfPresent(String.self, forKey: .keyCommand)
            if let doubleVal = try? container.decodeIfPresent(Double.self, forKey: .monthlyBudgetTarget) {
                self.monthlyBudgetTarget = doubleVal
            } else if let stringVal = try? container.decodeIfPresent(String.self, forKey: .monthlyBudgetTarget),
                      let parsed = Double(stringVal.trimmingCharacters(in: CharacterSet(charactersIn: "$ ").union(.whitespacesAndNewlines))) {
                self.monthlyBudgetTarget = parsed
            } else {
                self.monthlyBudgetTarget = nil
            }
            if let doubleVal = try? container.decodeIfPresent(Double.self, forKey: .spikeguardThreshold) {
                self.spikeguardThreshold = doubleVal
            } else if let stringVal = try? container.decodeIfPresent(String.self, forKey: .spikeguardThreshold),
                      let parsed = Double(stringVal.trimmingCharacters(in: CharacterSet(charactersIn: "$ ").union(.whitespacesAndNewlines))) {
                self.spikeguardThreshold = parsed
            } else {
                self.spikeguardThreshold = nil
            }
        }
    }

    public func loadConfigFile() -> PeekConfigFile? {
        let fileManager = FileManager.default
        let candidatePaths: [URL]
        if let custom = customConfigURL {
            candidatePaths = [custom]
        } else {
            let homeDir = fileManager.homeDirectoryForCurrentUser
            candidatePaths = [
                homeDir.appendingPathComponent(".config/peek-api/config.json"),
                homeDir.appendingPathComponent(".peek-api/config.json")
            ]
        }

        for url in candidatePaths {
            guard fileManager.fileExists(atPath: url.path),
                  let data = try? Data(contentsOf: url),
                  let config = try? JSONDecoder().decode(PeekConfigFile.self, from: data) else {
                continue
            }
            return config
        }
        return nil
    }

    private func updateConfigFile(_ mutate: (inout PeekConfigFile) -> Void) -> Bool {
        let fileManager = FileManager.default
        let configFile: URL
        if let custom = customConfigURL {
            configFile = custom
        } else {
            let configDir = fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".config/peek-api")
            configFile = configDir.appendingPathComponent("config.json")
        }

        var config = loadConfigFile() ?? PeekConfigFile()
        mutate(&config)

        do {
            try fileManager.createDirectory(at: configFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(config)
            try data.write(to: configFile, options: .atomic)
            invalidateCache()
            return true
        } catch {
            return false
        }
    }

    private func resolveFromConfigFile() -> String? {
        guard let config = loadConfigFile() else { return nil }

        if let staticKey = config.key?.trimmingCharacters(in: .whitespacesAndNewlines), !staticKey.isEmpty {
            return staticKey
        }

        if let cmd = config.keyCommand?.trimmingCharacters(in: .whitespacesAndNewlines), !cmd.isEmpty {
            if let output = executeKeyCommand(cmd) {
                return output
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
