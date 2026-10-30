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
    @Published public var inputKey: String = ""
    @Published public var isEditingKey: Bool = false
    @Published public var hoveredModelId: String? = nil
    @Published public private(set) var modelCatalog: [String: ModelCatalogItem] = [:]

    public var modelPricingMap: [String: ModelPricing] {
        modelCatalog.mapValues { $0.pricing }
    }

    // Budget Pacing Configurations
    public var monthlyBudget: Double = 25.00
    public var dailyBudget: Double {
        monthlyBudget / 30.0
    }

    private let client: OpenRouterClient
    private let keyResolver: KeyResolver
    private var pollingTimer: AnyCancellable?
    private var isRefreshing: Bool = false

    public init(client: OpenRouterClient = OpenRouterClient(), keyResolver: KeyResolver = .shared) {
        self.client = client
        self.keyResolver = keyResolver
        self.isKeyConfigured = keyResolver.resolveKey() != nil
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
        if isLoading && lastUpdated == nil {
            return "⚡ Loading..."
        }
        return "⚡ $\(String(format: "%.2f", todaySpend)) today"
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

        guard isKeyConfigured else {
            isLoading = false
            isRefreshing = false
            errorMessage = OpenRouterError.missingKey.localizedDescription
            return
        }

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

            // Refresh model catalog in background if not loaded or cache needs update
            Task { [weak self] in
                await self?.refreshModelCatalogIfNeeded()
            }
        } catch let error as OpenRouterError {
            self.errorMessage = error.localizedDescription
            if error == .missingKey || error == .unauthorized {
                self.isKeyConfigured = false
            }
        } catch {
            self.errorMessage = error.localizedDescription
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

    public func calculateStatus(for spend: Double) -> SpendingStatus {
        if spend < 0.80 {
            return .normal
        } else if spend <= 1.50 {
            return .warning
        } else {
            return .alert
        }
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
