import Foundation
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
                    "provider": "Muse",
                    "total_usage": 0.195
                },
                {
                    "model": "mimo/v2.5",
                    "provider": "OpenRouter",
                    "total_usage": 0.00709
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
            print("\n🎉 ALL CHECKS PASSED (6/6 suites)")
        } catch {
            print("❌ Check failed with error: \(error)")
            exit(1)
        }
    }
}
