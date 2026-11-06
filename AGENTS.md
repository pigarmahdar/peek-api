# AGENTS.md

## Project Overview
`peek-api` is a glanceable macOS menu bar companion for tracking real-time AI inference spending, BYOK (Bring Your Own Key) routing, and daily budget pacing on [OpenRouter](https://openrouter.ai). Built natively in Swift 5.9+ for macOS 13+ (Ventura), it utilizes SwiftUI (`MenuBarExtra`), AppKit, Combine, and URLSession with zero external runtime dependencies. It gives developers ambient awareness of API burn directly in their menu bar with no context switching.

## Verification Commands
Before opening a PR or submitting changes, agents MUST run:

```bash
# 1. Typecheck and build the debug targets
swift build

# 2. Run the full self-check test suite
swift run peek-check

# 3. (Optional) Verify release binary build
swift build -c release
```

*Note: There are no third-party linters (e.g. SwiftLint) or package managers (Cocoapods/npm). All dependencies are zero (`dependencies: []` in `Package.swift`). Building and testing requires a macOS environment with Xcode Command Line Tools (Swift 5.9+).*

## Architecture & Code Layout
* `Package.swift`: Defines the core targets (`PeekAPICore`, `PeekAPI`, `PeekAPICheck`) and CLI executables (`peek-api`, `peek`, `peek-check`).
* `Sources/PeekAPICore`: Pure Swift domain and networking library (zero UI imports):
  - `Models/OpenRouterData.swift`: Data envelopes (`CreditsEnvelope`, `ActivityItem`, `AnalyticsQueryEnvelope`), flexible JSON decoders (string/double floats), model slug normalization (`cleanName`, `lookupPricing`), and `SpendingStatus` / `ConnectionState` enums.
  - `Services/OpenRouterClient.swift`: Networking layer for `credits`, real-time `POST /api/v1/analytics/query` (primary), historical `GET /api/v1/activity` (fallback), and model catalog caching. Computes `startOfDay` and `startOfMonth` boundaries using local timezone (`TimeZone.current`).
  - `Services/KeyResolver.swift`: Thread-safe multi-tier secret resolver: `OPENROUTER_MANAGEMENT_KEY` env var → local `.env` → `OPENROUTER_KEY_COMMAND` CLI → `~/.config/peek-api/config.json`. Performs atomic, non-destructive config reads and writes.
  - `Services/SpendEngine.swift`: `@MainActor` state manager and 5-minute background poller. Calculates dynamic daily burn rate (`monthlyBudget / daysInMonth`) and pacing status (Normal ≤ 1.0×, Warning > 1.0×, Alert > 3.0×).
  - `Services/LaunchAtLoginManager.swift`: Handles macOS login items via `ServiceManagement` (`SMAppService.mainApp`) and CLI arguments (`login on/off/status`).
* `Sources/PeekAPI`: Native macOS UI executable target:
  - `App.swift`: `@main` entry point. Configures `.accessory` activation policy (menu bar only, hides from Dock) and mounts `SpendMenuView` in a `.window` style `MenuBarExtra`.
  - `Views/SpendMenuView.swift`: SwiftUI Control Center-styled popover displaying today's burn, pacing badge, top model spend breakdown (`🔑` BYOK vs `⚡` Wallet), hover pricing tooltips, wallet balance (`💳`), and settings panel.
* `Tests/PeekAPICheck`: Standalone regression test suite (`main.swift`) running 10 self-checks covering API decoding, BYOK detection, pacing math, timezone alignment, and state transitions.
* `bin/peek`: Shell wrapper for building, single-instance verification (`pgrep`), background launch (`nohup`), and CLI command routing.

## Development Guidelines
* **Minimal Diffs & YAGNI**: Keep changes small, readable, and strictly scoped to the task. Do not introduce speculative abstractions, wrappers, or unused configuration fields.
* **Concurrency & MainActor**: State and UI mutations in `SpendEngine` and `SpendMenuView` belong strictly on `@MainActor`. Networking in `OpenRouterClient` must remain async and `Sendable`.
* **Graceful Degradation**: Network errors and auth failures must update `ConnectionState` (`active`, `syncing`, `unauthorized`, `offline`) and present friendly user-facing messages rather than crashing. Use stale cached data (e.g. model catalog) when offline.
* **Test Coverage via Self-Checks**: Any alteration or addition to pricing logic, date calculation, status thresholds, or decoding MUST be accompanied by an assertion test in `Tests/PeekAPICheck/main.swift`.
* **Model Normalization**: Model IDs frequently change versions or carry date stamps (e.g. `-\\d{8}$`). Use `lookupPricing` / `lookupItem` and `ModelSpendSummary.cleanName` to handle variations cleanly.

## Hard Invariants & Anti-Patterns
* **ZERO External Runtime Dependencies**: NEVER add external Swift packages or third-party libraries to `Package.swift`. Stick exclusively to Apple system frameworks (`Foundation`, `SwiftUI`, `AppKit`, `Combine`, `ServiceManagement`).
* **NO UTC Hardcoding for Spend**: NEVER use UTC midnight (`secondsFromGMT: 0`) for today's spend boundaries. Always compute calendar cutoffs against the user's local timezone (`timeZone: TimeZone = .current`).
* **NO Sole Reliance on `/activity` for Today's Burn**: Real-time daily spend MUST query `POST /api/v1/analytics/query`. The `/activity` endpoint has batch lag and will misreport current-day usage (see `BUG_ACTIVITY_DISCREPANCY.md`).
* **NO Omitting BYOK Spend**: Upstream costs incurred via BYOK keys (`byok_usage_inference` / `byok_usage`) represent real dollars. Inference cost must always combine wallet cost and BYOK cost into `totalCost`.
* **NO Dock Icon or Standard Window**: Never remove `NSApplication.shared.setActivationPolicy(.accessory)` or change the app to a regular windowed app. It must remain purely in the menu bar.
* **NO Key Leakage or Destructive Config Writes**: Never log or expose management keys. When saving keys or budget values to `config.json`, always preserve existing keys/values atomically.
* **NO Aggressive Polling**: Polling frequency must remain around 5 minutes (`300s`) to avoid rate limits and unnecessary battery drain.
