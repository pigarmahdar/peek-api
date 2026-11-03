import SwiftUI
import PeekAPICore

@MainActor
public struct SpendMenuView: View {
    @ObservedObject var engine: SpendEngine
    @ObservedObject var launchManager: LaunchAtLoginManager

    public init(engine: SpendEngine, launchManager: LaunchAtLoginManager? = nil) {
        self.engine = engine
        self.launchManager = launchManager ?? .shared
    }

    private var statusColor: Color {
        switch engine.status {
        case .normal: return .green
        case .warning: return .orange
        case .alert: return .red
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !engine.isKeyConfigured || engine.isEditingKey {
                settingsSection
            } else {
                burnHeaderSection
                modelsSection
                walletSection
            }

            if let error = engine.errorMessage, engine.isKeyConfigured && !engine.isEditingKey {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal, 4)
            }

            Divider()
                .opacity(0.6)
            actionsFooterSection
        }
        .padding(14)
        .frame(width: 320)
    }

    // MARK: - Sections

    @ViewBuilder
    private var burnHeaderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Today's Burn", systemImage: "flame.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)

                Spacer()

                if engine.isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 14, height: 14)
                } else {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 6, height: 6)
                        Text(engine.status.label)
                            .font(.caption2.weight(.medium))
                            .foregroundColor(statusColor)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(statusColor.opacity(0.12))
                    .clipShape(Capsule())
                }
            }

            HStack(alignment: .firstTextBaseline) {
                Text("Daily Spend / Target")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                HStack(spacing: 2) {
                    Text("$\(String(format: "%.2f", engine.todaySpend))")
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                    Text("/ $\(String(format: "%.2f", engine.dailyBudget))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
            }

            HStack(alignment: .firstTextBaseline) {
                Text("Month to Date")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("$\(String(format: "%.2f", engine.monthSpend)) / $\(String(format: "%.2f", engine.monthlyBudget))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                Text("(\(engine.monthPercentage)%)")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private var modelsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Top Models Today")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)

            if engine.models.isEmpty {
                Text("No inference activity recorded today")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                VStack(spacing: 4) {
                    ForEach(engine.models.prefix(5)) { item in
                        modelRow(for: item)
                    }
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private func modelRow(for item: ModelSpendSummary) -> some View {
        let isHovered = (engine.hoveredModelId == item.rawModelId)
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: item.isBYOK ? "key.fill" : "bolt.fill")
                    .font(.system(size: 10))
                    .foregroundColor(item.isBYOK ? .orange : .blue)
                    .frame(width: 14)

                Text(item.displayName)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                Text("$\(String(format: "%.2f", item.cost))")
                    .font(.callout.weight(.medium))
                    .monospacedDigit()

                Text("(\(Int(item.percentage))%)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                    .frame(minWidth: 36, alignment: .trailing)
            }

            if isHovered, let pricing = item.pricing {
                HStack(spacing: 4) {
                    Text("Input: $\(String(format: "%.2f", pricing.promptPerMillion))/1M")
                    Text("•")
                        .opacity(0.4)
                    Text("Output: $\(String(format: "%.2f", pricing.completionPerMillion))/1M")
                }
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.leading, 20)
                .padding(.top, 1)
                .transition(.opacity)
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(isHovered ? Color.primary.opacity(0.06) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovered in
            withAnimation(.easeInOut(duration: 0.12)) {
                engine.hoveredModelId = hovered ? item.rawModelId : nil
            }
        }
        .help(item.pricingTooltip)
    }

    @ViewBuilder
    private var walletSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "creditcard.fill")
                .foregroundColor(.secondary)
                .font(.subheadline)
            Text("OpenRouter Wallet")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text("$\(String(format: "%.2f", engine.walletBalance)) left")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private var actionsFooterSection: some View {
        HStack {
            if !engine.isEditingKey && engine.isKeyConfigured {
                Button(action: {
                    Task {
                        await engine.refresh()
                    }
                }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)

                Spacer()

                Button(action: {
                    if let url = URL(string: "https://openrouter.ai/activity/explore?metric=total_usage&granularity=day&date_preset=month_to_date") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    Label("Dashboard", systemImage: "globe")
                }
                .buttonStyle(.borderless)

                Spacer()

                Button(action: {
                    engine.inputBudget = String(format: "%.2f", engine.monthlyBudget)
                    engine.budgetErrorMessage = nil
                    engine.isEditingKey = true
                }) {
                    Label("Settings", systemImage: "gearshape")
                }
                .buttonStyle(.borderless)

                Spacer()
            }

            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                Text("Quit")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .font(.caption)
    }

    @ViewBuilder
    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Settings", systemImage: "gearshape.fill")
                    .font(.headline)
                Spacer()
                if engine.isEditingKey && engine.isKeyConfigured {
                    Button("Done") {
                        engine.isEditingKey = false
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }

            budgetCard
            startupCard
            keyCard
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var budgetCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Monthly Budget Target", systemImage: "target")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("$\(String(format: "%.2f", engine.dailyBudget))/day")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }

            Text("Set your monthly spend limit. Pacing warnings (🟡 >1.0×) and alerts (🔴 >3.0×) adjust automatically to days in the month.")
                .font(.caption2)
                .foregroundColor(.secondary)

            HStack(spacing: 6) {
                Text("$")
                    .foregroundColor(.secondary)
                    .font(.callout.weight(.medium))

                TextField("25.00", text: $engine.inputBudget)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        engine.saveBudget(engine.inputBudget)
                    }

                Button("Save Budget") {
                    engine.saveBudget(engine.inputBudget)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(engine.inputBudget.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let error = engine.budgetErrorMessage {
                Text(error)
                    .font(.caption2)
                    .foregroundColor(.red)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private var startupCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Launch at Login", systemImage: "macwindow")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Toggle("", isOn: Binding(
                    get: { launchManager.isEnabled },
                    set: { launchManager.setLaunchAtLogin($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
            }

            Text("Start peek-api automatically when logging into macOS.")
                .font(.caption2)
                .foregroundColor(.secondary)

            if launchManager.status == .requiresApproval {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                    Text("Disabled in macOS Settings")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Open Settings") {
                        launchManager.openSystemSettings()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption2.weight(.medium))
                }
                .padding(6)
                .background(Color.orange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            if let error = launchManager.errorMessage {
                Text(error)
                    .font(.caption2)
                    .foregroundColor(.red)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private var keyCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("OpenRouter Key", systemImage: "key.fill")
                .font(.subheadline.weight(.semibold))

            Text("Paste your OpenRouter Management Key (`sk-or-v1-...`) to track real-time inference burn.")
                .font(.caption2)
                .foregroundColor(.secondary)

            SecureField("sk-or-v1-...", text: $engine.inputKey)
                .textFieldStyle(.roundedBorder)

            HStack {
                Text("Saved to ~/.config/peek-api/config.json")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Save Key") {
                    Task {
                        let success = await engine.saveKey(engine.inputKey)
                        if success {
                            engine.isEditingKey = false
                            engine.inputKey = ""
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(engine.inputKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
