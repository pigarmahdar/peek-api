import SwiftUI
import PeekAPICore

public struct SpendMenuView: View {
    @ObservedObject var engine: SpendEngine

    public init(engine: SpendEngine) {
        self.engine = engine
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
                setupKeySection
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
                Text("Daily Spend")
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
                        .padding(.vertical, 1)
                    }
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                    if let url = URL(string: "https://openrouter.ai/activity") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    Label("Dashboard", systemImage: "globe")
                }
                .buttonStyle(.borderless)

                Spacer()

                Button(action: {
                    engine.isEditingKey = true
                }) {
                    Label("Key", systemImage: "key")
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
    private var setupKeySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("OpenRouter Key", systemImage: "key.fill")
                    .font(.headline)
                Spacer()
                if engine.isEditingKey && engine.isKeyConfigured {
                    Button("Cancel") {
                        engine.isEditingKey = false
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }

            Text("Paste your OpenRouter Management Key (`sk-or-v1-...`) to track real-time inference burn.")
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                SecureField("sk-or-v1-...", text: $engine.inputKey)
                    .textFieldStyle(.roundedBorder)

                HStack {
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

            Text("Key is saved locally to ~/.config/peek-api/config.json")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}
