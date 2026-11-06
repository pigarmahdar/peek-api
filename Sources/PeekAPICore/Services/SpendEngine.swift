import Foundation
import Combine

@MainActor
public final class SpendEngine: ObservableObject {
    @Published public var todaySpend: Double = 0.0
    @Published public var monthSpend: Double = 0.0
    @Published public var walletBalance: Double = 0.0
    @Published public var models: [ModelSpendSummary] = []
    @Published public var status: SpendingStatus = .normal
    @Published public var isLoading: Bool = false
    @Published public var lastUpdated: Date?
    @Published public var errorMessage: String?
    @Published public var isKeyConfigured: Bool = false
    @Published public var connectionState: ConnectionState = .offline
    @Published public var inputKey: String = ""
    @Published public var isEditingKey: Bool = false
    @Published public var hoveredModelId: String? = nil
    @Published public private(set) var modelCatalog: [String: ModelCatalogItem] = [:]

    public var modelPricingMap: [String: ModelPricing] {
        modelCatalog.mapValues { $0.pricing }
    }

    // Budget Pacing Configurations
    @Published public var monthlyBudget: Double = 25.00
    @Published public var inputBudget: String = "25.00"
    @Published public var budgetErrorMessage: String? = nil

    public var dailyBudget: Double {
        Self.calculateDailyRate(monthlyBudget: monthlyBudget, on: Date())
    }

    public static func daysInMonth(for date: Date = Date(), calendar: Calendar = .current) -> Int {
        calendar.range(of: .day, in: .month, for: date)?.count ?? 30
    }

    public static func calculateDailyRate(monthlyBudget: Double, on date: Date = Date(), calendar: Calendar = .current) -> Double {
        guard monthlyBudget > 0 else { return 0.0 }
        let days = Double(daysInMonth(for: date, calendar: calendar))
        return monthlyBudget / days
    }

    private let client: OpenRouterClient
    private let keyResolver: KeyResolver
    private var pollingTimer: AnyCancellable?
    private var isRefreshing: Bool = false

    public init(client: OpenRouterClient = OpenRouterClient(), keyResolver: KeyResolver = .shared) {
        self.client = client
        self.keyResolver = keyResolver
        self.isKeyConfigured = keyResolver.resolveKey() != nil
        self.connectionState = self.isKeyConfigured ? .offline : .unauthorized
        if let configuredBudget = keyResolver.resolveBudgetTarget(), configuredBudget > 0 {
            self.monthlyBudget = configuredBudget
        }
        self.inputBudget = String(format: "%.2f", self.monthlyBudget)
        if let cached = client.loadCachedModelCatalog() {
            self.modelCatalog = cached
        }
        Task { [weak self] in
            await self?.refreshModelCatalogIfNeeded()
        }
    }

    // MARK: - Menu Bar Display Strings

    public var menuBarTitle: String {
        if !isKeyConfigured {
            return "⚡ Setup Key"
        }
        if connectionState == .unauthorized {
            return "⚡ Key Error"
        }
        if connectionState == .syncing && lastUpdated == nil {
            return "⚡ Loading..."
        }
        if connectionState == .offline {
            if lastUpdated != nil {
                return "⚡ $\(String(format: "%.2f", todaySpend)) today ⚠️"
            } else {
                return "⚡ Offline"
            }
        }
        return "⚡ $\(String(format: "%.2f", todaySpend)) today"
    }

    public static func relativeTimeString(from date: Date, to now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 {
            return "just now"
        }
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)m ago"
        }
        let hours = minutes / 60
        if hours < 24 {
            return "\(hours)h ago"
        }
        let days = hours / 24
        return "\(days)d ago"
    }

    public func footerStatusText(relativeTo now: Date = Date()) -> String {
        switch connectionState {
        case .syncing:
            return "Syncing..."
        case .unauthorized:
            return isKeyConfigured ? "Invalid Management Key" : "No Management Key"
        case .offline:
            if let last = lastUpdated {
                return "Offline · Synced \(Self.relativeTimeString(from: last, to: now))"
            } else {
                return "Offline"
            }
        case .active:
            if let last = lastUpdated {
                return "Synced \(Self.relativeTimeString(from: last, to: now))"
            } else {
                return "Active"
            }
        }
    }

    public var monthPercentage: Int {
        guard monthlyBudget > 0 else { return 0 }
        return Int((monthSpend / monthlyBudget) * 100.0)
    }

    // MARK: - Polling & Refresh

    public func startPolling(interval: TimeInterval = 300) { // 5 minutes default
        Task {
            await refresh()
        }

        pollingTimer?.cancel()
        pollingTimer = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.refresh()
                }
            }
    }

    public func stopPolling() {
        pollingTimer?.cancel()
        pollingTimer = nil
    }

    public func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        isLoading = true
        errorMessage = nil

        let resolvedKey = keyResolver.resolveKey()
        isKeyConfigured = resolvedKey != nil
        if let configuredBudget = keyResolver.resolveBudgetTarget(), configuredBudget > 0 {
            self.monthlyBudget = configuredBudget
            if !isEditingKey {
                self.inputBudget = String(format: "%.2f", configuredBudget)
            }
        }

        guard isKeyConfigured else {
            isLoading = false
            isRefreshing = false
            connectionState = .unauthorized
            errorMessage = OpenRouterError.missingKey.localizedDescription
            return
        }

        connectionState = .syncing

        do {
            async let creditsTask = client.fetchCredits()
            async let activityTask = client.fetchActivity(modelPricing: self.modelPricingMap)

            let (credits, activity) = try await (creditsTask, activityTask)

            self.walletBalance = credits.remainingBalance
            self.todaySpend = activity.todaySpend
            self.monthSpend = activity.monthToDateSpend
            self.models = activity.topModelsToday
            self.status = calculateStatus(for: activity.todaySpend)
            self.lastUpdated = Date()
            self.errorMessage = nil
            self.connectionState = .active

            // Refresh model catalog in background if not loaded or cache needs update
            Task { [weak self] in
                await self?.refreshModelCatalogIfNeeded()
            }
        } catch let error as OpenRouterError {
            self.errorMessage = error.localizedDescription
            if error == .missingKey || error == .unauthorized {
                self.connectionState = .unauthorized
            } else {
                self.connectionState = .offline
            }
        } catch {
            self.errorMessage = error.localizedDescription
            self.connectionState = .offline
        }

        isLoading = false
        isRefreshing = false
    }

    public func refreshModelCatalogIfNeeded(forceRefresh: Bool = false) async {
        do {
            let catalog = try await client.fetchModelCatalog(forceRefresh: forceRefresh)
            self.modelCatalog = catalog
            attachPricingToModels()
        } catch {
            // Non-fatal background error
        }
    }

    public func findCatalogItem(for modelId: String) -> ModelCatalogItem? {
        modelCatalog.lookupItem(for: modelId)
    }

    private func attachPricingToModels() {
        guard !modelCatalog.isEmpty else { return }
        self.models = self.models.map { item in
            guard item.pricing == nil, let catalogItem = findCatalogItem(for: item.rawModelId) else {
                return item
            }
            return ModelSpendSummary(
                rawModelId: item.rawModelId,
                displayName: item.displayName,
                cost: item.cost,
                percentage: item.percentage,
                isBYOK: item.isBYOK,
                pricing: catalogItem.pricing
            )
        }
    }

    public func calculateStatus(for spend: Double, dailyRate: Double? = nil) -> SpendingStatus {
        let rate = dailyRate ?? dailyBudget
        guard rate > 0 else {
            return spend > 0 ? .alert : .normal
        }
        if spend > rate * 3.0 {
            return .alert
        } else if spend > rate * 1.0 {
            return .warning
        } else {
            return .normal
        }
    }

    @discardableResult
    public func saveBudget(_ text: String) -> Bool {
        let cleaned = text.trimmingCharacters(in: CharacterSet(charactersIn: "$ ").union(.whitespacesAndNewlines))
        guard let value = Double(cleaned), value > 0 else {
            self.budgetErrorMessage = "Enter a valid budget amount (> $0)"
            return false
        }
        self.budgetErrorMessage = nil
        self.monthlyBudget = value
        self.inputBudget = String(format: "%.2f", value)
        self.status = calculateStatus(for: todaySpend)
        return keyResolver.saveBudgetTarget(value)
    }

    public func saveKey(_ key: String) async -> Bool {
        let success = keyResolver.saveKey(key)
        if success {
            self.isKeyConfigured = true
            await refresh()
        }
        return success
    }
}
