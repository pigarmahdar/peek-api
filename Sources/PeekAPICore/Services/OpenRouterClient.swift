import Foundation

public enum OpenRouterError: LocalizedError, Equatable {
    case missingKey
    case unauthorized
    case httpError(statusCode: Int, message: String?)
    case networkError(String)
    case decodingError(String)

    public var errorDescription: String? {
        switch self {
        case .missingKey:
            return "No OpenRouter Management Key found. Configure via Bitwarden (OPENROUTER_KEY_COMMAND), ~/.config/peek-api/config.json, or OPENROUTER_MANAGEMENT_KEY."
        case .unauthorized:
            return "Authentication failed (401/403). Ensure you are using an OpenRouter Management Key (sk-or-v1-...)."
        case .httpError(let code, let msg):
            return "OpenRouter API returned HTTP \(code): \(msg ?? "Unknown error")"
        case .networkError(let msg):
            return "Network error: \(msg)"
        case .decodingError(let msg):
            return "Failed to parse API response: \(msg)"
        }
    }
}

public struct ActivitySnapshot: Equatable {
    public let todayDateUTC: String
    public let todaySpend: Double
    public let monthToDateSpend: Double
    public let topModelsToday: [ModelSpendSummary]
    public let allTodayItems: [ActivityItem]

    public init(
        todayDateUTC: String,
        todaySpend: Double,
        monthToDateSpend: Double,
        topModelsToday: [ModelSpendSummary],
        allTodayItems: [ActivityItem]
    ) {
        self.todayDateUTC = todayDateUTC
        self.todaySpend = todaySpend
        self.monthToDateSpend = monthToDateSpend
        self.topModelsToday = topModelsToday
        self.allTodayItems = allTodayItems
    }
}

public final class OpenRouterClient: Sendable {
    private let session: URLSession
    private let keyResolver: KeyResolver

    public init(session: URLSession = .shared, keyResolver: KeyResolver = .shared) {
        self.session = session
        self.keyResolver = keyResolver
    }

    // MARK: - Public API

    public func fetchCredits() async throws -> CreditsData {
        guard let key = keyResolver.resolveKey() else {
            throw OpenRouterError.missingKey
        }

        let url = URL(string: "https://openrouter.ai/api/v1/credits")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await performRequest(request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenRouterError.networkError("Invalid response type")
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            keyResolver.invalidateCache()
            throw OpenRouterError.unauthorized
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMsg = String(data: data, encoding: .utf8)
            throw OpenRouterError.httpError(statusCode: httpResponse.statusCode, message: errorMsg)
        }

        do {
            let envelope = try JSONDecoder().decode(CreditsEnvelope.self, from: data)
            return envelope.data
        } catch {
            // Also try direct CreditsData in case API format varies
            if let direct = try? JSONDecoder().decode(CreditsData.self, from: data) {
                return direct
            }
            throw OpenRouterError.decodingError(error.localizedDescription)
        }
    }

    public func fetchActivity(now: Date = Date(), timeZone: TimeZone = .current) async throws -> ActivitySnapshot {
        guard let key = keyResolver.resolveKey() else {
            throw OpenRouterError.missingKey
        }

        let historicalItems = try await fetchHistoricalActivity(key: key)

        // Attempt real-time query for today's in-flight spend
        if let realtimeItems = try? await fetchRealtimeTodaySpend(key: key, now: now, timeZone: timeZone) {
            return processWithRealtime(historical: historicalItems, realtime: realtimeItems, relativeTo: now, timeZone: timeZone)
        }

        return processActivityItems(historicalItems, relativeTo: now, timeZone: timeZone)
    }

    public func fetchRealtimeTodaySpend(
        key: String? = nil,
        now: Date = Date(),
        timeZone: TimeZone = .current
    ) async throws -> [AnalyticsQueryItem] {
        guard let resolvedKey = key ?? keyResolver.resolveKey() else {
            throw OpenRouterError.missingKey
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let startOfDay = calendar.startOfDay(for: now)

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        let startISO = isoFormatter.string(from: startOfDay)
        let endISO = isoFormatter.string(from: now)

        let url = URL(string: "https://openrouter.ai/api/v1/analytics/query")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(resolvedKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let query = AnalyticsQueryRequest(
            metrics: ["total_usage", "byok_usage"],
            dimensions: ["model"],
            timeRange: .init(start: startISO, end: endISO)
        )
        request.httpBody = try JSONEncoder().encode(query)

        let (data, response) = try await performRequest(request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenRouterError.networkError("Invalid response type")
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            keyResolver.invalidateCache()
            throw OpenRouterError.unauthorized
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMsg = String(data: data, encoding: .utf8)
            throw OpenRouterError.httpError(statusCode: httpResponse.statusCode, message: errorMsg)
        }

        let envelope = try JSONDecoder().decode(AnalyticsQueryEnvelope.self, from: data)
        return envelope.items
    }

    private func fetchHistoricalActivity(key: String) async throws -> [ActivityItem] {
        let url = URL(string: "https://openrouter.ai/api/v1/activity")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await performRequest(request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenRouterError.networkError("Invalid response type")
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            keyResolver.invalidateCache()
            throw OpenRouterError.unauthorized
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMsg = String(data: data, encoding: .utf8)
            throw OpenRouterError.httpError(statusCode: httpResponse.statusCode, message: errorMsg)
        }

        if let envelope = try? JSONDecoder().decode(ActivityEnvelope.self, from: data) {
            return envelope.data
        } else if let items = try? JSONDecoder().decode([ActivityItem].self, from: data) {
            return items
        } else {
            throw OpenRouterError.decodingError("Unable to decode activity items")
        }
    }

    // MARK: - Internal Processing

    public func processWithRealtime(
        historical: [ActivityItem],
        realtime: [AnalyticsQueryItem],
        relativeTo now: Date,
        timeZone: TimeZone = .current
    ) -> ActivitySnapshot {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let todayString = formatter.string(from: now)

        formatter.dateFormat = "yyyy-MM"
        let currentMonthString = formatter.string(from: now)

        var todaySpend: Double = 0.0
        var modelSpendAccumulator: [String: (cost: Double, isBYOK: Bool)] = [:]
        var todayItems: [ActivityItem] = []

        for item in realtime {
            guard let model = item.model else { continue }
            let cost = item.cost
            todaySpend += cost

            let current = modelSpendAccumulator[model] ?? (cost: 0.0, isBYOK: false)
            modelSpendAccumulator[model] = (
                cost: current.cost + cost,
                isBYOK: current.isBYOK || item.isBYOK
            )

            let byokCost = item.byokUsage ?? (item.isBYOK ? cost : 0.0)
            let walletCost = max(0.0, cost - byokCost)

            todayItems.append(ActivityItem(
                date: todayString,
                model: model,
                providerName: item.provider,
                usage: walletCost,
                byokUsageInference: byokCost,
                requests: nil
            ))
        }

        // Sum historical completed days for current month excluding today to prevent double-counting
        var monthSpend: Double = 0.0
        for item in historical {
            if item.date.hasPrefix(currentMonthString) && item.date != todayString {
                monthSpend += item.totalCost
            }
        }
        monthSpend += todaySpend

        let sortedModels = modelSpendAccumulator
            .sorted { $0.value.cost > $1.value.cost }
            .map { modelId, tuple in
                let percentage = todaySpend > 0 ? (tuple.cost / todaySpend) * 100.0 : 0.0
                return ModelSpendSummary(
                    rawModelId: modelId,
                    displayName: ModelSpendSummary.cleanName(for: modelId),
                    cost: tuple.cost,
                    percentage: percentage,
                    isBYOK: tuple.isBYOK
                )
            }

        return ActivitySnapshot(
            todayDateUTC: todayString,
            todaySpend: todaySpend,
            monthToDateSpend: monthSpend,
            topModelsToday: sortedModels,
            allTodayItems: todayItems
        )
    }

    public func processActivityItems(_ items: [ActivityItem], relativeTo now: Date, timeZone: TimeZone = .current) -> ActivitySnapshot {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let todayString = formatter.string(from: now)

        formatter.dateFormat = "yyyy-MM"
        let currentMonthString = formatter.string(from: now)

        var todaySpend: Double = 0.0
        var monthSpend: Double = 0.0
        var todayItems: [ActivityItem] = []
        var modelSpendAccumulator: [String: (cost: Double, isBYOK: Bool)] = [:]

        for item in items {
            let itemCost = item.totalCost

            if item.date.hasPrefix(currentMonthString) {
                monthSpend += itemCost
            }

            if item.date == todayString {
                todaySpend += itemCost
                todayItems.append(item)

                let current = modelSpendAccumulator[item.model] ?? (cost: 0.0, isBYOK: false)
                modelSpendAccumulator[item.model] = (
                    cost: current.cost + itemCost,
                    isBYOK: current.isBYOK || item.isBYOK
                )
            }
        }

        let sortedModels = modelSpendAccumulator
            .sorted { $0.value.cost > $1.value.cost }
            .map { modelId, tuple in
                let percentage = todaySpend > 0 ? (tuple.cost / todaySpend) * 100.0 : 0.0
                return ModelSpendSummary(
                    rawModelId: modelId,
                    displayName: ModelSpendSummary.cleanName(for: modelId),
                    cost: tuple.cost,
                    percentage: percentage,
                    isBYOK: tuple.isBYOK
                )
            }

        return ActivitySnapshot(
            todayDateUTC: todayString,
            todaySpend: todaySpend,
            monthToDateSpend: monthSpend,
            topModelsToday: sortedModels,
            allTodayItems: todayItems
        )
    }

    private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw OpenRouterError.networkError(error.localizedDescription)
        }
    }
}
