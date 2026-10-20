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

    public func startPolling(interval: TimeInterval = 900) { // 15 minutes default
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
            async let activityTask = client.fetchActivity()

            let (credits, activity) = try await (creditsTask, activityTask)

            self.walletBalance = credits.remainingBalance
            self.todaySpend = activity.todaySpend
            self.monthSpend = activity.monthToDateSpend
            self.models = activity.topModelsToday
            self.status = calculateStatus(for: activity.todaySpend)
            self.lastUpdated = Date()
            self.errorMessage = nil
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
