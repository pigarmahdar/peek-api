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
    public let cacheFileURL: URL

    public init(session: URLSession = .shared, keyResolver: KeyResolver = .shared, cacheFileURL: URL? = nil) {
        self.session = session
        self.keyResolver = keyResolver
        self.cacheFileURL = cacheFileURL ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/peek-api/models_cache.json")
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

    public func fetchActivity(
        now: Date = Date(),
        timeZone: TimeZone = .current,
        modelPricing: [String: ModelPricing] = [:]
    ) async throws -> ActivitySnapshot {
        guard let key = keyResolver.resolveKey() else {
            throw OpenRouterError.missingKey
        }

        // Attempt real-time queries for today and month-to-date in parallel
        do {
            async let todayTask = fetchRealtimeSpend(key: key, from: startOfDay(for: now, timeZone: timeZone), to: now)
            async let monthTask = fetchRealtimeSpend(key: key, from: startOfMonth(for: now, timeZone: timeZone), to: now)

            let (realtimeToday, realtimeMonth) = try await (todayTask, monthTask)
            return processRealtimeSnapshot(
                today: realtimeToday,
                month: realtimeMonth,
                relativeTo: now,
                timeZone: timeZone,
                modelPricing: modelPricing
            )
        } catch {
            // Fallback to historical activity endpoint
            let historicalItems = try await fetchHistoricalActivity(key: key)
            return processActivityItems(
                historicalItems,
                relativeTo: now,
                timeZone: timeZone,
                modelPricing: modelPricing
            )
        }
    }

    public func fetchRealtimeTodaySpend(
        key: String? = nil,
        now: Date = Date(),
        timeZone: TimeZone = .current
    ) async throws -> [AnalyticsQueryItem] {
        try await fetchRealtimeSpend(key: key, from: startOfDay(for: now, timeZone: timeZone), to: now)
    }

    public func fetchRealtimeSpend(
        key: String? = nil,
        from startDate: Date,
        to endDate: Date
    ) async throws -> [AnalyticsQueryItem] {
        guard let resolvedKey = key ?? keyResolver.resolveKey() else {
            throw OpenRouterError.missingKey
        }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        let startISO = isoFormatter.string(from: startDate)
        let endISO = isoFormatter.string(from: endDate)

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

    public func startOfDay(for date: Date, timeZone: TimeZone = .current) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.startOfDay(for: date)
    }

    public func startOfMonth(for date: Date, timeZone: TimeZone = .current) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    public func processRealtimeSnapshot(
        today: [AnalyticsQueryItem],
        month: [AnalyticsQueryItem],
        relativeTo now: Date,
        timeZone: TimeZone = .current,
        modelPricing: [String: ModelPricing] = [:]
    ) -> ActivitySnapshot {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let todayString = formatter.string(from: now)

        var todaySpend: Double = 0.0
        var modelSpendAccumulator: [String: (cost: Double, isBYOK: Bool)] = [:]
        var todayItems: [ActivityItem] = []

        for item in today {
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

        let monthSpend = month.reduce(0.0) { $0 + $1.cost }

        let sortedModels = modelSpendAccumulator
            .sorted { $0.value.cost > $1.value.cost }
            .map { modelId, tuple in
                let percentage = todaySpend > 0 ? (tuple.cost / todaySpend) * 100.0 : 0.0
                return ModelSpendSummary(
                    rawModelId: modelId,
                    displayName: ModelSpendSummary.cleanName(for: modelId),
                    cost: tuple.cost,
                    percentage: percentage,
                    isBYOK: tuple.isBYOK,
                    pricing: modelPricing.lookupPricing(for: modelId)
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

    public func processWithRealtime(
        historical: [ActivityItem],
        realtime: [AnalyticsQueryItem],
        relativeTo now: Date,
        timeZone: TimeZone = .current,
        modelPricing: [String: ModelPricing] = [:]
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
            if item.date.hasPrefix(currentMonthString) && !item.date.hasPrefix(todayString) {
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
                    isBYOK: tuple.isBYOK,
                    pricing: modelPricing.lookupPricing(for: modelId)
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

    public func processActivityItems(
        _ items: [ActivityItem],
        relativeTo now: Date,
        timeZone: TimeZone = .current,
        modelPricing: [String: ModelPricing] = [:]
    ) -> ActivitySnapshot {
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

            if item.date.hasPrefix(todayString) {
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
                    isBYOK: tuple.isBYOK,
                    pricing: modelPricing.lookupPricing(for: modelId)
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

    // MARK: - Model Catalog & Pricing

    public struct ModelsCacheEnvelope: Codable, Sendable {
        public let timestamp: Date
        public let models: [String: ModelCatalogItem]

        public init(timestamp: Date = Date(), models: [String: ModelCatalogItem]) {
            self.timestamp = timestamp
            self.models = models
        }
    }

    public func loadCachedModelCatalog(maxAge: TimeInterval = 6 * 3600) -> [String: ModelCatalogItem]? {
        let url = cacheFileURL
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let envelope = try? JSONDecoder().decode(ModelsCacheEnvelope.self, from: data) else {
            return nil
        }
        if Date().timeIntervalSince(envelope.timestamp) < maxAge {
            return envelope.models
        }
        return nil
    }

    public func saveModelCatalogToCache(_ models: [String: ModelCatalogItem]) {
        let envelope = ModelsCacheEnvelope(timestamp: Date(), models: models)
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        let url = cacheFileURL
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    public func fetchModelCatalog(forceRefresh: Bool = false) async throws -> [String: ModelCatalogItem] {
        if !forceRefresh, let cached = loadCachedModelCatalog() {
            return cached
        }

        let url = URL(string: "https://openrouter.ai/api/v1/models")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let key = keyResolver.resolveKey() {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await performRequest(request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                if let stale = loadCachedModelCatalog(maxAge: TimeInterval.greatestFiniteMagnitude) {
                    return stale
                }
                throw OpenRouterError.networkError("Failed to fetch model catalog")
            }

            let envelope = try JSONDecoder().decode(ModelCatalogEnvelope.self, from: data)
            var map: [String: ModelCatalogItem] = [:]
            for item in envelope.data {
                map[item.id] = item
            }
            saveModelCatalogToCache(map)
            return map
        } catch {
            if let stale = loadCachedModelCatalog(maxAge: TimeInterval.greatestFiniteMagnitude) {
                return stale
            }
            throw error
        }
    }

    private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw OpenRouterError.networkError(error.localizedDescription)
        }
    }
}
