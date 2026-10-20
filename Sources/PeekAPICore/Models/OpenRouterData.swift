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
        byokCost > 0 || (providerName != nil && providerName?.lowercased() != "openrouter")
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
    public let usage: Double?

    enum CodingKeys: String, CodingKey {
        case model
        case provider
        case totalUsage = "total_usage"
        case usage
    }

    public init(model: String?, provider: String? = nil, totalUsage: Double? = nil, usage: Double? = nil) {
        self.model = model
        self.provider = provider
        self.totalUsage = totalUsage
        self.usage = usage
    }

    public var cost: Double {
        totalUsage ?? usage ?? 0.0
    }

    public var isBYOK: Bool {
        if let provider = provider, provider.lowercased() != "openrouter" {
            return true
        }
        return false
    }
}

public struct ModelSpendSummary: Identifiable, Equatable {
    public var id: String { rawModelId }
    public let rawModelId: String
    public let displayName: String
    public let cost: Double
    public let percentage: Double
    public let isBYOK: Bool

    public init(rawModelId: String, displayName: String, cost: Double, percentage: Double, isBYOK: Bool) {
        self.rawModelId = rawModelId
        self.displayName = displayName
        self.cost = cost
        self.percentage = percentage
        self.isBYOK = isBYOK
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
