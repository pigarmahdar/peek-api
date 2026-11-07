import Foundation

public struct CreditsEnvelope: Codable {
    public let data: CreditsData

    public init(data: CreditsData) {
        self.data = data
    }
}

public struct CreditsData: Codable, Equatable {
    public let totalCredits: Double
    public let totalUsage: Double

    public var remainingBalance: Double {
        max(0, totalCredits - totalUsage)
    }

    enum CodingKeys: String, CodingKey {
        case totalCredits = "total_credits"
        case totalUsage = "total_usage"
    }

    public init(totalCredits: Double, totalUsage: Double) {
        self.totalCredits = totalCredits
        self.totalUsage = totalUsage
    }
}

public struct ActivityEnvelope: Codable {
    public let data: [ActivityItem]

    public init(data: [ActivityItem]) {
        self.data = data
    }
}

public struct ActivityItem: Codable, Equatable {
    public let date: String
    public let model: String
    public let providerName: String?
    public let usage: Double?
    public let byokUsageInference: Double?
    public let requests: Int?

    enum CodingKeys: String, CodingKey {
        case date
        case model
        case providerName = "provider_name"
        case usage
        case byokUsageInference = "byok_usage_inference"
        case requests
    }

    public init(
        date: String,
        model: String,
        providerName: String? = nil,
        usage: Double? = nil,
        byokUsageInference: Double? = nil,
        requests: Int? = nil
    ) {
        self.date = date
        self.model = model
        self.providerName = providerName
        self.usage = usage
        self.byokUsageInference = byokUsageInference
        self.requests = requests
    }

    public var walletCost: Double {
        usage ?? 0.0
    }

    public var byokCost: Double {
        byokUsageInference ?? 0.0
    }

    public var totalCost: Double {
        walletCost + byokCost
    }

    public var isBYOK: Bool {
        byokCost > 0
    }
}

public struct AnalyticsQueryRequest: Codable {
    public struct TimeRange: Codable {
        public let start: String
        public let end: String

        public init(start: String, end: String) {
            self.start = start
            self.end = end
        }
    }

    public let metrics: [String]
    public let dimensions: [String]
    public let timeRange: TimeRange

    enum CodingKeys: String, CodingKey {
        case metrics
        case dimensions
        case timeRange = "time_range"
    }

    public init(metrics: [String], dimensions: [String], timeRange: TimeRange) {
        self.metrics = metrics
        self.dimensions = dimensions
        self.timeRange = timeRange
    }
}

public struct AnalyticsQueryEnvelope: Codable {
    public struct InnerData: Codable {
        public let data: [AnalyticsQueryItem]
    }

    public let items: [AnalyticsQueryItem]

    enum CodingKeys: String, CodingKey {
        case data
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let inner = try? container.decode(InnerData.self, forKey: .data) {
            self.items = inner.data
        } else if let list = try? container.decode([AnalyticsQueryItem].self, forKey: .data) {
            self.items = list
        } else {
            self.items = []
        }
    }

    public init(items: [AnalyticsQueryItem]) {
        self.items = items
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(items, forKey: .data)
    }
}

public struct AnalyticsQueryItem: Codable, Equatable {
    public let model: String?
    public let provider: String?
    public let totalUsage: Double?
    public let byokUsage: Double?
    public let usage: Double?

    enum CodingKeys: String, CodingKey {
        case model
        case provider
        case totalUsage = "total_usage"
        case byokUsage = "byok_usage"
        case usage
    }

    public init(
        model: String?,
        provider: String? = nil,
        totalUsage: Double? = nil,
        byokUsage: Double? = nil,
        usage: Double? = nil
    ) {
        self.model = model
        self.provider = provider
        self.totalUsage = totalUsage
        self.byokUsage = byokUsage
        self.usage = usage
    }

    public var cost: Double {
        totalUsage ?? usage ?? 0.0
    }

    public var isBYOK: Bool {
        (byokUsage ?? 0.0) > 0
    }
}

public struct PricingOverride: Codable, Equatable, Sendable {
    public let utcDays: [String]?
    public let utcStart: Int?
    public let utcEnd: Int?
    public let minPromptTokens: Int?
    public let prompt: Double?
    public let completion: Double?
    public let request: Double?
    public let image: Double?

    public init(
        utcDays: [String]? = nil,
        utcStart: Int? = nil,
        utcEnd: Int? = nil,
        minPromptTokens: Int? = nil,
        prompt: Double? = nil,
        completion: Double? = nil,
        request: Double? = nil,
        image: Double? = nil
    ) {
        self.utcDays = utcDays
        self.utcStart = utcStart
        self.utcEnd = utcEnd
        self.minPromptTokens = minPromptTokens
        self.prompt = prompt
        self.completion = completion
        self.request = request
        self.image = image
    }

    enum CodingKeys: String, CodingKey {
        case utcDays = "utc_days"
        case utcStart = "utc_start"
        case utcEnd = "utc_end"
        case minPromptTokens = "min_prompt_tokens"
        case prompt, completion, request, image
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.utcDays = try? container.decodeIfPresent([String].self, forKey: .utcDays)
        self.utcStart = Self.decodeFlexibleInt(container, key: .utcStart)
        self.utcEnd = Self.decodeFlexibleInt(container, key: .utcEnd)
        self.minPromptTokens = Self.decodeFlexibleInt(container, key: .minPromptTokens)
        self.prompt = Self.decodeFlexibleDouble(container, key: .prompt)
        self.completion = Self.decodeFlexibleDouble(container, key: .completion)
        self.request = Self.decodeFlexibleDouble(container, key: .request)
        self.image = Self.decodeFlexibleDouble(container, key: .image)
    }

    private static func decodeFlexibleDouble(_ container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> Double? {
        if let d = try? container.decode(Double.self, forKey: key) {
            return d
        }
        if let s = try? container.decode(String.self, forKey: key), let d = Double(s) {
            return d
        }
        return nil
    }

    private static func decodeFlexibleInt(_ container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> Int? {
        if let i = try? container.decode(Int.self, forKey: key) {
            return i
        }
        if let s = try? container.decode(String.self, forKey: key), let i = Int(s) {
            return i
        }
        return nil
    }
}

public struct ModelPricing: Codable, Equatable, Sendable {
    public let prompt: Double
    public let completion: Double
    public let request: Double?
    public let image: Double?
    public let overrides: [PricingOverride]?

    public var promptPerMillion: Double { effectivePromptPerMillion() }
    public var completionPerMillion: Double { effectiveCompletionPerMillion() }

    public init(
        prompt: Double,
        completion: Double,
        request: Double? = nil,
        image: Double? = nil,
        overrides: [PricingOverride]? = nil
    ) {
        self.prompt = prompt
        self.completion = completion
        self.request = request
        self.image = image
        self.overrides = overrides
    }

    enum CodingKeys: String, CodingKey {
        case prompt, completion, request, image, overrides
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.prompt = Self.decodeFlexibleDouble(container, key: .prompt) ?? 0.0
        self.completion = Self.decodeFlexibleDouble(container, key: .completion) ?? 0.0
        self.request = Self.decodeFlexibleDouble(container, key: .request)
        self.image = Self.decodeFlexibleDouble(container, key: .image)
        self.overrides = try? container.decodeIfPresent([PricingOverride].self, forKey: .overrides)
    }

    private static func decodeFlexibleDouble(_ container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> Double? {
        if let d = try? container.decode(Double.self, forKey: key) {
            return d
        }
        if let s = try? container.decode(String.self, forKey: key), let d = Double(s) {
            return d
        }
        return nil
    }

    public func effectiveRates(at date: Date = Date()) -> (prompt: Double, completion: Double) {
        guard let overrides = overrides, !overrides.isEmpty else {
            return (prompt, completion)
        }

        var calendar = Calendar(identifier: .gregorian)
        guard let utc = TimeZone(secondsFromGMT: 0) else {
            return (prompt, completion)
        }
        calendar.timeZone = utc

        let weekdayIndex = calendar.component(.weekday, from: date) - 1 // 0 = Sunday
        let dayNames = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        let currentDay = dayNames[max(0, min(6, weekdayIndex))]
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let currentTime = hour * 100 + minute

        for override in overrides {
            if override.minPromptTokens != nil {
                continue
            }

            if let days = override.utcDays, !days.isEmpty {
                let normalized = days.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                if !normalized.contains(currentDay) {
                    continue
                }
            }

            if override.utcStart != nil || override.utcEnd != nil {
                let start = override.utcStart ?? 0
                let rawEnd = override.utcEnd ?? 0
                let end = rawEnd == 0 ? 2400 : rawEnd

                if start < end {
                    guard currentTime >= start && currentTime < end else {
                        continue
                    }
                } else if start > end {
                    guard currentTime >= start || currentTime < end else {
                        continue
                    }
                }
            }

            if override.prompt != nil || override.completion != nil {
                return (override.prompt ?? prompt, override.completion ?? completion)
            }
        }

        return (prompt, completion)
    }

    public func effectivePrompt(at date: Date = Date()) -> Double {
        effectiveRates(at: date).prompt
    }

    public func effectiveCompletion(at date: Date = Date()) -> Double {
        effectiveRates(at: date).completion
    }

    public func effectivePromptPerMillion(at date: Date = Date()) -> Double {
        effectivePrompt(at: date) * 1_000_000
    }

    public func effectiveCompletionPerMillion(at date: Date = Date()) -> Double {
        effectiveCompletion(at: date) * 1_000_000
    }
}

public struct ModelCatalogItem: Codable, Equatable, Sendable {
    public let id: String
    public let name: String?
    public let contextLength: Int?
    public let pricing: ModelPricing

    enum CodingKeys: String, CodingKey {
        case id, name, pricing
        case contextLength = "context_length"
    }

    public init(id: String, name: String? = nil, contextLength: Int? = nil, pricing: ModelPricing) {
        self.id = id
        self.name = name
        self.contextLength = contextLength
        self.pricing = pricing
    }
}

public struct ModelCatalogEnvelope: Codable, Sendable {
    public let data: [ModelCatalogItem]

    public init(data: [ModelCatalogItem]) {
        self.data = data
    }
}

public struct ModelSpendSummary: Identifiable, Equatable, Sendable {
    public var id: String { rawModelId }
    public let rawModelId: String
    public let displayName: String
    public let cost: Double
    public let percentage: Double
    public let isBYOK: Bool
    public let pricing: ModelPricing?

    public init(
        rawModelId: String,
        displayName: String,
        cost: Double,
        percentage: Double,
        isBYOK: Bool,
        pricing: ModelPricing? = nil
    ) {
        self.rawModelId = rawModelId
        self.displayName = displayName
        self.cost = cost
        self.percentage = percentage
        self.isBYOK = isBYOK
        self.pricing = pricing
    }

    public var pricingTooltip: String {
        pricingTooltip(at: Date())
    }

    public func pricingTooltip(at date: Date = Date()) -> String {
        guard let pricing = pricing else {
            return "Pricing unavailable"
        }
        return """
        Input:  $\(String(format: "%.2f", pricing.effectivePromptPerMillion(at: date))) / 1M tokens
        Output: $\(String(format: "%.2f", pricing.effectiveCompletionPerMillion(at: date))) / 1M tokens
        """
    }

    public static func cleanName(for modelId: String) -> String {
        let parts = modelId.split(separator: "/")
        var rawName = parts.count > 1 ? String(parts[1]) : modelId
        if let match = rawName.range(of: "-\\d{8}$", options: .regularExpression) {
            rawName.removeSubrange(match)
        }
        return rawName
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }
}

public enum SpendingStatus: Equatable {
    case normal  // < $0.80
    case warning // $0.80 - $1.50
    case alert   // > $1.50

    public var emoji: String {
        switch self {
        case .normal: return "🟢"
        case .warning: return "🟡"
        case .alert: return "🔴"
        }
    }

    public var label: String {
        switch self {
        case .normal: return "On Track"
        case .warning: return "Pacing Warning"
        case .alert: return "High Burn"
        }
    }
}

public enum ConnectionState: String, Equatable, Sendable {
    case active
    case syncing
    case unauthorized
    case offline
}

public struct SpikeAlert: Equatable, Sendable {
    public let delta: Double
    public let topModel: String
    public let timestamp: Date
    public let isOvernight: Bool

    public init(delta: Double, topModel: String, timestamp: Date = Date(), isOvernight: Bool = false) {
        self.delta = delta
        self.topModel = topModel
        self.timestamp = timestamp
        self.isOvernight = isOvernight
    }
}

public extension Dictionary where Key == String, Value == ModelPricing {
    func lookupPricing(for modelId: String) -> ModelPricing? {
        if let direct = self[modelId] {
            return direct
        }
        var normalized = modelId
        if let match = normalized.range(of: "-\\d{8}$", options: .regularExpression) {
            normalized.removeSubrange(match)
            if let matchItem = self[normalized] {
                return matchItem
            }
        }
        if let colonIndex = normalized.firstIndex(of: ":") {
            let baseId = String(normalized[..<colonIndex])
            if let baseMatch = self[baseId] {
                return baseMatch
            }
        }
        for (k, v) in self {
            if k.hasPrefix(normalized) {
                return v
            }
        }
        return nil
    }
}

public extension Dictionary where Key == String, Value == ModelCatalogItem {
    func lookupItem(for modelId: String) -> ModelCatalogItem? {
        if let direct = self[modelId] {
            return direct
        }
        var normalized = modelId
        if let match = normalized.range(of: "-\\d{8}$", options: .regularExpression) {
            normalized.removeSubrange(match)
            if let matchItem = self[normalized] {
                return matchItem
            }
        }
        if let colonIndex = normalized.firstIndex(of: ":") {
            let baseId = String(normalized[..<colonIndex])
            if let baseMatch = self[baseId] {
                return baseMatch
            }
        }
        for (k, v) in self {
            if k.hasPrefix(normalized) {
                return v
            }
        }
        return nil
    }
}
