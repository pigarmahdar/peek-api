import Foundation
import ServiceManagement
import PeekAPICore

func testCreditsDecoding() throws {
    let json = """
    {
        "data": {
            "total_credits": 25.50,
            "total_usage": 7.10
        }
    }
    """.data(using: .utf8)!

    let envelope = try JSONDecoder().decode(CreditsEnvelope.self, from: json)
    assert(envelope.data.totalCredits == 25.50, "totalCredits mismatch")
    assert(envelope.data.totalUsage == 7.10, "totalUsage mismatch")
    assert(abs(envelope.data.remainingBalance - 18.40) < 0.001, "remainingBalance mismatch")
    print("  ✅ Credits decoding & balance check passed")
}

func testActivityProcessingAndGrouping() {
    let client = OpenRouterClient()
    let fixedDate = Date(timeIntervalSince1970: 1776600000)
    let formatter = DateFormatter()
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    let todayString = formatter.string(from: fixedDate)

    let items = [
        ActivityItem(
            date: todayString,
            model: "google/gemini-2.5-flash",
            providerName: "Google",
            usage: 0.0,
            byokUsageInference: 0.28,
            requests: 10
        ),
        ActivityItem(
            date: todayString,
            model: "deepseek/deepseek-chat",
            providerName: "DeepSeek",
            usage: 0.0,
            byokUsageInference: 0.11,
            requests: 5
        ),
        ActivityItem(
            date: todayString,
            model: "anthropic/claude-3.5-haiku",
            providerName: "OpenRouter",
            usage: 0.07,
            byokUsageInference: 0.0,
            requests: 2
        ),
        ActivityItem(
            date: "2020-01-01",
            model: "openai/gpt-4o",
            providerName: "OpenAI",
            usage: 1.50,
            byokUsageInference: 0.0,
            requests: 1
        )
    ]

    let snapshot = client.processActivityItems(items, relativeTo: fixedDate)

    assert(abs(snapshot.todaySpend - 0.46) < 0.001, "todaySpend mismatch")
    assert(snapshot.topModelsToday.count == 3, "topModelsToday count mismatch")

    let gemini = snapshot.topModelsToday[0]
    assert(gemini.rawModelId == "google/gemini-2.5-flash", "first model mismatch")
    assert(abs(gemini.cost - 0.28) < 0.001, "gemini cost mismatch")
    assert(gemini.isBYOK == true, "gemini isBYOK mismatch")

    let deepseek = snapshot.topModelsToday[1]
    assert(deepseek.rawModelId == "deepseek/deepseek-chat", "second model mismatch")
    assert(deepseek.isBYOK == true, "deepseek isBYOK mismatch")

    let claude = snapshot.topModelsToday[2]
    assert(claude.rawModelId == "anthropic/claude-3.5-haiku", "third model mismatch")
    assert(claude.isBYOK == false, "claude isBYOK mismatch")

    print("  ✅ Activity aggregation, BYOK detection & ranking passed")
}

func testModelCleanNames() {
    assert(ModelSpendSummary.cleanName(for: "google/gemini-2.5-flash") == "Gemini 2.5 Flash", "cleanName mismatch")
    assert(ModelSpendSummary.cleanName(for: "anthropic/claude-3.5-haiku") == "Claude 3.5 Haiku", "cleanName mismatch")
    assert(ModelSpendSummary.cleanName(for: "deepseek/deepseek-r1") == "Deepseek R1", "cleanName mismatch")
    print("  ✅ Model display name cleaning passed")
}

@MainActor
func testSpendEngineThresholds() {
    let engine = SpendEngine()
    assert(engine.calculateStatus(for: 0.0) == .normal, "0.0 status mismatch")
    assert(engine.calculateStatus(for: 0.46) == .normal, "0.46 status mismatch")
    assert(engine.calculateStatus(for: 0.79) == .normal, "0.79 status mismatch")

    assert(engine.calculateStatus(for: 0.80) == .warning, "0.80 status mismatch")
    assert(engine.calculateStatus(for: 1.20) == .warning, "1.20 status mismatch")
    assert(engine.calculateStatus(for: 1.50) == .warning, "1.50 status mismatch")

    assert(engine.calculateStatus(for: 1.51) == .alert, "1.51 status mismatch")
    assert(engine.calculateStatus(for: 3.50) == .alert, "3.50 status mismatch")

    engine.isKeyConfigured = false
    assert(engine.menuBarTitle == "⚡ Setup Key", "menuBarTitle unconfigured mismatch")

    engine.isKeyConfigured = true
    engine.todaySpend = 0.46
    assert(engine.menuBarTitle == "⚡ $0.46 today", "menuBarTitle formatted mismatch")

    engine.monthlyBudget = 25.00
    engine.monthSpend = 12.50
    assert(engine.monthPercentage == 50, "monthPercentage mismatch")

    print("  ✅ SpendEngine pacing thresholds & UI strings passed")
}

func testKeyResolverCommandAndConfig() throws {
    let resolver = KeyResolver()
    let echoResult = resolver.executeKeyCommand("echo 'sk-or-v1-bw-secret-demo'")
    assert(echoResult == "sk-or-v1-bw-secret-demo", "executeKeyCommand echo mismatch")

    let failResult = resolver.executeKeyCommand("exit 1")
    assert(failResult == nil, "executeKeyCommand failure mismatch")

    let jsonWithKey = """
    {
        "key": "sk-or-v1-direct"
    }
    """.data(using: .utf8)!

    let config1 = try JSONDecoder().decode(KeyResolver.PeekConfigFile.self, from: jsonWithKey)
    assert(config1.key == "sk-or-v1-direct", "config1 key mismatch")
    assert(config1.keyCommand == nil, "config1 keyCommand mismatch")

    let jsonWithCommand = """
    {
        "key_command": "bw get password openrouter-management"
    }
    """.data(using: .utf8)!

    let config2 = try JSONDecoder().decode(KeyResolver.PeekConfigFile.self, from: jsonWithCommand)
    assert(config2.keyCommand == "bw get password openrouter-management", "config2 keyCommand mismatch")
    assert(config2.key == nil, "config2 key mismatch")

    // Test .env parsing
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    let dotEnvContent = """
    # Comments
    SOME_VAR=hello
    OPENROUTER_MANAGEMENT_KEY="sk-or-v1-dotenv-secret"
    """
    try dotEnvContent.write(to: tmpDir.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
    let envParsed = resolver.resolveFromDotEnv(directory: tmpDir.path)
    assert(envParsed == "sk-or-v1-dotenv-secret", "dotEnv parsing mismatch")
    try? FileManager.default.removeItem(at: tmpDir)

    print("  ✅ KeyResolver command execution, config file decoding & .env parsing passed")
}

func testRealtimeAnalyticsProcessingAndMerging() throws {
    let json = """
    {
        "data": {
            "data": [
                {
                    "model": "muse/spark-1.3-contributor",
                    "total_usage": 0.195,
                    "byok_usage": 0.195
                },
                {
                    "model": "mimo/v2.5",
                    "total_usage": 0.00709,
                    "byok_usage": 0.0
                }
            ]
        }
    }
    """.data(using: .utf8)!

    let envelope = try JSONDecoder().decode(AnalyticsQueryEnvelope.self, from: json)
    assert(envelope.items.count == 2, "AnalyticsQueryEnvelope item count mismatch")
    assert(envelope.items[0].cost == 0.195, "first item cost mismatch")
    assert(envelope.items[0].isBYOK == true, "first item isBYOK mismatch")
    assert(envelope.items[1].isBYOK == false, "second item isBYOK mismatch")

    let sgt = TimeZone(secondsFromGMT: 8 * 3600)!
    let client = OpenRouterClient()

    // 2026-10-20 13:00:00 SGT = 2026-10-20 05:00:00 UTC = 1792472400
    let testDate = Date(timeIntervalSince1970: 1792472400)

    let historical = [
        ActivityItem(date: "2026-10-18", model: "openai/gpt-4o", usage: 5.00),
        ActivityItem(date: "2026-10-19", model: "openai/gpt-4o", usage: 5.90)
    ]

    let snapshot = client.processWithRealtime(
        historical: historical,
        realtime: envelope.items,
        relativeTo: testDate,
        timeZone: sgt
    )

    assert(snapshot.todayDateUTC == "2026-10-20", "today date mismatch under SGT")
    assert(abs(snapshot.todaySpend - 0.20209) < 0.0001, "todaySpend mismatch")
    assert(abs(snapshot.monthToDateSpend - (10.90 + 0.20209)) < 0.0001, "monthToDateSpend mismatch")
    assert(snapshot.topModelsToday.count == 2, "topModelsToday count mismatch")
    assert(snapshot.topModelsToday[0].displayName == "Spark 1.3 Contributor", "top model name mismatch")
    assert(snapshot.topModelsToday[0].isBYOK == true, "top model BYOK mismatch")
    assert(snapshot.topModelsToday[1].isBYOK == false, "second model BYOK mismatch")

    print("  ✅ Real-time Analytics query decoding, SGT timezone & spend merging passed")
}

func testRealtimeSnapshotAndDateFormatAlignment() throws {
    let client = OpenRouterClient()
    let sgt = TimeZone(secondsFromGMT: 8 * 3600)!
    let testDate = Date(timeIntervalSince1970: 1792472400) // 2026-10-20 13:00 SGT

    // 1. Test processRealtimeSnapshot
    let todayItems = [
        AnalyticsQueryItem(model: "xiaomi/mimo-v2.6-flash-20260921", totalUsage: 0.66, byokUsage: 0.64),
        AnalyticsQueryItem(model: "deepseek/deepseek-v4.1-flash-20261017", totalUsage: 0.46, byokUsage: 0.30)
    ]
    let monthItems = [
        AnalyticsQueryItem(model: "qwen/qwen3.8-omni-flash-20260918", totalUsage: 3.12),
        AnalyticsQueryItem(model: "anthropic/claude-haiku-5.5-20261007", totalUsage: 2.29),
        AnalyticsQueryItem(model: "xiaomi/mimo-v2.6-flash-20260921", totalUsage: 0.66),
        AnalyticsQueryItem(model: "deepseek/deepseek-v4.1-flash-20261017", totalUsage: 0.46)
    ]

    let snapshot = client.processRealtimeSnapshot(today: todayItems, month: monthItems, relativeTo: testDate, timeZone: sgt)
    assert(snapshot.todayDateUTC == "2026-10-20", "today date mismatch")
    assert(abs(snapshot.todaySpend - 1.12) < 0.001, "todaySpend mismatch")
    assert(abs(snapshot.monthToDateSpend - 6.53) < 0.001, "monthToDateSpend mismatch")
    assert(snapshot.topModelsToday.count == 2, "topModelsToday count mismatch")
    assert(snapshot.topModelsToday[0].displayName == "Mimo V2.6 Flash", "top model display name mismatch")
    assert(snapshot.topModelsToday[0].isBYOK == true, "top model BYOK mismatch")

    // 2. Test date format handling with OpenRouter's "YYYY-MM-DD 00:00:00" strings in activity fallback
    let activityWithTimestamps = [
        ActivityItem(date: "2026-10-20 00:00:00", model: "openai/gpt-4o", usage: 0.75),
        ActivityItem(date: "2026-10-19 00:00:00", model: "openai/gpt-4o", usage: 1.25)
    ]
    let fallbackSnapshot = client.processActivityItems(activityWithTimestamps, relativeTo: testDate, timeZone: sgt)
    assert(abs(fallbackSnapshot.todaySpend - 0.75) < 0.001, "fallback todaySpend should match timestamped date")
    assert(abs(fallbackSnapshot.monthToDateSpend - 2.00) < 0.001, "fallback monthToDateSpend mismatch")

    // 3. Test that processWithRealtime excludes timestamped today from historical items
    let merged = client.processWithRealtime(historical: activityWithTimestamps, realtime: todayItems, relativeTo: testDate, timeZone: sgt)
    assert(abs(merged.todaySpend - 1.12) < 0.001, "merged today spend mismatch")
    assert(abs(merged.monthToDateSpend - (1.25 + 1.12)) < 0.001, "merged month spend should exclude today's historical item")

    print("  ✅ Real-time Snapshot & OpenRouter timestamped activity date alignment passed")
}

final class MockLaunchService: LaunchServiceProtocol {
    var status: SMAppService.Status = .notRegistered
    var shouldFail: Bool = false
    var openedSystemSettings: Bool = false

    func register() throws {
        if shouldFail {
            throw NSError(domain: "SMAppServiceError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Permission denied"])
        }
        status = .enabled
    }

    func unregister() throws {
        if shouldFail {
            throw NSError(domain: "SMAppServiceError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unregister failed"])
        }
        status = .notRegistered
    }

    func openSystemSettings() {
        openedSystemSettings = true
    }
}

@MainActor
func testLaunchAtLoginManager() {
    let mock = MockLaunchService()
    let manager = LaunchAtLoginManager(service: mock)

    assert(!manager.isEnabled, "Initial state should be disabled")
    assert(manager.status == .notRegistered, "Initial status should be notRegistered")

    // Test enabling
    manager.setLaunchAtLogin(true)
    assert(manager.isEnabled, "Should be enabled after setLaunchAtLogin(true)")
    assert(manager.status == .enabled, "Status should be enabled")
    assert(manager.errorMessage == nil, "Error message should be nil")

    // Test disabling
    manager.setLaunchAtLogin(false)
    assert(!manager.isEnabled, "Should be disabled after setLaunchAtLogin(false)")
    assert(manager.status == .notRegistered, "Status should be notRegistered")

    // Test failure handling
    mock.shouldFail = true
    manager.setLaunchAtLogin(true)
    assert(!manager.isEnabled, "Should remain disabled on failure")
    assert(manager.errorMessage != nil, "Error message should be set on failure")

    // Test requires approval state
    mock.shouldFail = false
    mock.status = .requiresApproval
    manager.refreshStatus()
    assert(!manager.isEnabled, "requiresApproval should not be considered enabled")
    assert(manager.status == .requiresApproval, "Status should reflect requiresApproval")

    // Test openSystemSettings
    manager.openSystemSettings()
    assert(mock.openedSystemSettings, "openSystemSettings should delegate to service")

    // Test CLI argument parsing
    assert(LaunchAtLoginManager.handleCommandLineArgs(["peek", "api", "login", "status"], manager: manager) == true)
    assert(LaunchAtLoginManager.handleCommandLineArgs(["peek", "api", "login", "on"], manager: manager) == true)
    assert(LaunchAtLoginManager.handleCommandLineArgs(["peek", "api", "login", "off"], manager: manager) == true)
    assert(LaunchAtLoginManager.handleCommandLineArgs(["peek", "api"], manager: manager) == false)
    assert(LaunchAtLoginManager.handleCommandLineArgs(["peek"], manager: manager) == false)

    print("  ✅ LaunchAtLoginManager registration, unregistration, status & CLI checks passed")
}

func testModelPricingDecodingAndTooltip() throws {
    let json = """
    {
        "data": [
            {
                "id": "deepseek/deepseek-chat",
                "name": "DeepSeek: DeepSeek V3",
                "context_length": 64000,
                "pricing": {
                    "prompt": "0.00000014",
                    "completion": "0.00000028"
                }
            },
            {
                "id": "anthropic/claude-3.5-sonnet",
                "name": "Claude 3.5 Sonnet",
                "context_length": 200000,
                "pricing": {
                    "prompt": 0.000003,
                    "completion": 0.000015
                }
            }
        ]
    }
    """.data(using: .utf8)!

    let envelope = try JSONDecoder().decode(ModelCatalogEnvelope.self, from: json)
    assert(envelope.data.count == 2, "Model catalog count mismatch")

    let deepseek = envelope.data[0]
    assert(deepseek.id == "deepseek/deepseek-chat", "Model ID mismatch")
    assert(abs(deepseek.pricing.promptPerMillion - 0.14) < 0.001, "DeepSeek promptPerMillion mismatch")
    assert(abs(deepseek.pricing.completionPerMillion - 0.28) < 0.001, "DeepSeek completionPerMillion mismatch")

    let sonnet = envelope.data[1]
    assert(abs(sonnet.pricing.promptPerMillion - 3.00) < 0.001, "Sonnet promptPerMillion mismatch")
    assert(abs(sonnet.pricing.completionPerMillion - 15.00) < 0.001, "Sonnet completionPerMillion mismatch")

    // Verify ModelSpendSummary tooltip formatting
    let summaryWithPricing = ModelSpendSummary(
        rawModelId: deepseek.id,
        displayName: "DeepSeek V3",
        cost: 0.11,
        percentage: 24.0,
        isBYOK: true,
        pricing: deepseek.pricing
    )
    let expectedTooltip = "Input:  $0.14 / 1M tokens\nOutput: $0.28 / 1M tokens"
    assert(summaryWithPricing.pricingTooltip == expectedTooltip, "Tooltip text mismatch:\n'\(summaryWithPricing.pricingTooltip)' vs '\(expectedTooltip)'")

    let summaryWithoutPricing = ModelSpendSummary(
        rawModelId: "custom/unknown",
        displayName: "Unknown",
        cost: 0.05,
        percentage: 10.0,
        isBYOK: false
    )
    assert(summaryWithoutPricing.pricingTooltip == "Pricing unavailable", "Fallback tooltip mismatch")

    // Verify OpenRouterClient caching with isolated temp file
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("peek_test_cache_\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: tempURL) }
    let client = OpenRouterClient(cacheFileURL: tempURL)
    var catalogMap: [String: ModelCatalogItem] = [:]
    for item in envelope.data {
        catalogMap[item.id] = item
    }
    client.saveModelCatalogToCache(catalogMap)

    let loaded = client.loadCachedModelCatalog(maxAge: 3600)
    assert(loaded != nil, "Failed to load cached model catalog")
    assert(loaded?["deepseek/deepseek-chat"]?.pricing.promptPerMillion == deepseek.pricing.promptPerMillion, "Cached item mismatch")

    // Verify date-versioned slug lookup
    let pricingMap = catalogMap.mapValues { $0.pricing }
    assert(catalogMap.lookupItem(for: "deepseek/deepseek-chat-20261017")?.id == "deepseek/deepseek-chat", "Date slug item lookup mismatch")
    assert(pricingMap.lookupPricing(for: "anthropic/claude-3.5-sonnet-20260922")?.promptPerMillion == 3.00, "Date slug pricing lookup mismatch")

    print("  ✅ Model pricing decoding (string/float), per-million math, tooltip & disk cache checks passed")
}

// MARK: - Main Test Runner
@main
struct PeekCheckRunner {
    static func main() async {
        print("🚀 Running peek-api self-checks...")
        do {
            try testCreditsDecoding()
            testActivityProcessingAndGrouping()
            testModelCleanNames()
            testSpendEngineThresholds()
            try testKeyResolverCommandAndConfig()
            try testRealtimeAnalyticsProcessingAndMerging()
            try testRealtimeSnapshotAndDateFormatAlignment()
            testLaunchAtLoginManager()
            try testModelPricingDecodingAndTooltip()
            print("\n🎉 ALL CHECKS PASSED (9/9 suites)")
        } catch {
            print("❌ Check failed with error: \(error)")
            exit(1)
        }
    }
}
