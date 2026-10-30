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

public struct ModelPricing: Codable, Equatable, Sendable {
    public let prompt: Double
    public let completion: Double
    public let request: Double?
    public let image: Double?

    public var promptPerMillion: Double { prompt * 1_000_000 }
    public var completionPerMillion: Double { completion * 1_000_000 }

    public init(prompt: Double, completion: Double, request: Double? = nil, image: Double? = nil) {
        self.prompt = prompt
        self.completion = completion
        self.request = request
        self.image = image
    }

    enum CodingKeys: String, CodingKey {
        case prompt, completion, request, image
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.prompt = Self.decodeFlexibleDouble(container, key: .prompt) ?? 0.0
        self.completion = Self.decodeFlexibleDouble(container, key: .completion) ?? 0.0
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
        guard let pricing = pricing else {
            return "Pricing unavailable"
        }
        return """
        Input:  $\(String(format: "%.2f", pricing.promptPerMillion)) / 1M tokens
        Output: $\(String(format: "%.2f", pricing.completionPerMillion)) / 1M tokens
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
