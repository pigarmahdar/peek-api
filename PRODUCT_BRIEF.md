# Product Brief: `peek-api`

> A glanceable macOS menu bar companion for tracking real-time AI inference spending, BYOK routing, and daily budget pacing.

---

## 1. Executive Summary & Problem

Developers and power users running automated harnesses, multi-agent frameworks, and coding tools (Cursor, Cline, custom agent scripts) face a common problem: **spend anxiety and context switching**. 

To check burn rate, token volume, or remaining balances, users are forced to repeatedly switch to a browser, log into OpenRouter or multiple provider dashboards, and tally up their numbers.

### Core Value Proposition
* **Ambient Awareness:** Total visibility over daily API spending directly in the macOS menu bar without switching windows or breaking flow.
* **The "ChatGPT Plus Arbitrage" Tracker:** Enables users to pace their inference against a fixed monthly budget (e.g., $25/month) designed to replace standard flat-rate subscriptions with flexible API usage.
* **BYOK & Flash Efficiency Visibility:** Unified tracking that captures both OpenRouter credit deductions and direct upstream provider costs (Google AI Studio, DeepSeek, Xiaomi, Perplexity).

---

## 2. Target User & Persona

* **The Efficiency-Obsessed AI Builder:** Uses primarily flash, lightweight, or cheap models (Gemini Flash, DeepSeek V3/R1, Claude Haiku) for heavy automated tasks.
* **BYOK Power User:** Has configured multiple third-party API keys within OpenRouter to minimize markups and maximize volume.
* **Self-Paced Harness Runner:** Runs deep eval loops or heavy batch jobs and needs an immediate speedometer to catch runaway loops or accidental expensive fallbacks before they burn through monthly capital.

---

## 3. Product Principles

1. **Glanceable Over Comprehensive:** The menu bar must communicate health in under 1 second.
2. **Unified Cost (Real Dollars):** Money spent via BYOK accounts (DeepSeek, Google, etc.) is still real money. The app tracks *total true inference cost*, not just wallet balance deductions.
3. **Pacing, Not Just Accounting:** Show spending relative to daily targets ($0.83/day on a $25/month ceiling) to guide pacing.
4. **Emoji-First Visual Language:** Use compact, standardized emojis (`🔑`, `⚡`, `🟢`, `🟡`, `🔴`, `💳`) to maximize data density without visual clutter.

---

## 4. User Experience & Interface Specifications

### A. Menu Bar Item (Always Visible)

```text
⚡ $0.46 today
```

* **Content:** Combined daily inference spend (BYOK + OpenRouter wallet).
* **Color / Status Indicator:**
  * 🟢 **Normal (< $0.80):** Under daily target budget.
  * 🟡 **Pacing Warning ($0.80 – $1.50):** Borrowing budget from future days.
  * 🔴 **Alert (> $1.50):** Runaway loop or heavy unexpected burn.

---

### B. Dropdown Menu (On Click)

```text
┌──────────────────────────────────────────────┐
│  📊 TODAY'S INFERENCE BURN                   │
│  Spend:      $0.46 / $0.83      🟢 On Track  │
│  Month:      $12.30 / $25.00    (49%)        │
│  ──────────────────────────────────────────  │
│  MODEL SPEND (TODAY)                         │
│  • 🔑 Gemini 2.5 Flash        $0.28   (61%)  │
│  • 🔑 DeepSeek V3             $0.11   (24%)  │
│  • ⚡ Claude 3.5 Haiku        $0.07   (15%)  │
│  ──────────────────────────────────────────  │
│  💳 OpenRouter Wallet:        $18.40 left    │
│  ──────────────────────────────────────────  │
│  🔄 Refresh              🌐 Open Dashboard   │
└──────────────────────────────────────────────┘
```

#### Signal Legend:
* **`🔑` (BYOK):** Handled via direct provider API keys (Google, DeepSeek, Xiaomi, Perplexity).
* **`⚡` (OpenRouter Wallet):** Handled via OpenRouter credits / platform models.
* **`💳` (Wallet Balance):** Bottom-anchored balance indicator to alert when a top-up deposit is required.

---

## 5. Technical Architecture & Data Strategy

### A. Data Sources (OpenRouter API)

1. **Daily Activity & Model Breakdown:**
   * **Endpoint:** `GET https://openrouter.ai/api/v1/activity`
   * **Auth:** OpenRouter Management API Key (`Bearer sk-or-v1-...`)
   * **Data Extracted:**
     * `date`: Filter for current UTC day.
     * `model`: Cleaned model names for single-line display.
     * `cost`: Actual inference dollar cost (includes BYOK list-price estimates).
     * `provider`: Upstream provider identifier (used to determine `🔑` vs `⚡`).
2. **Wallet Balance:**
   * **Endpoint:** `GET https://openrouter.ai/api/v1/credits`
   * **Data Extracted:** `total_credits - total_usage` = remaining wallet balance.

### B. Polling Strategy & Performance
* **Background Polling:** Every 10–15 minutes (avoids rate limits and preserves battery life).
* **Immediate Refresh:** Triggered manually via the "🔄 Refresh" button or automatically when the user opens the dropdown.
* **Local Storage / Keychain:** Management API key stored securely in the macOS Keychain (`Security.framework`). User preferences (monthly budget cap, polling interval) stored in standard `UserDefaults`.

---

## 6. Implementation Roadmap

### Phase 1: Rapid Prototype (Day 1)
* Minimal script using **SwiftBar** or lightweight Python/Bash runner.
* Validates OpenRouter `/activity` and `/credits` JSON payloads with the user's specific BYOK keys.
* Confirms correct emoji parsing and menubar item rendering.

### Phase 2: Standalone Native macOS App (Day 2–3)
* Native Swift app using SwiftUI `MenuBarExtra` (macOS 13+ Ventura and newer).
* Zero dependencies, tiny binary footprint (<5MB), zero idling CPU/RAM impact.
* Direct macOS Keychain integration for secure API key storage.
* Preferences window: Configure Monthly Cap (default $25), Warning Thresholds, Polling Interval.

### Phase 3: Polish & Distribution
* Single-click .DMG release or Homebrew formula (`brew install --cask peek-api`).
* Optional notification alerts on threshold crossing (e.g. "Daily spend exceeded $1.00").

---

## 7. Out of Scope (YAGNI for V1)

* Historical charting and interactive multi-week analytics (use the OpenRouter web dashboard).
* Multi-account or multi-workspace switching.
* Outbound webhook listeners (polling is sufficient and simpler).
* Direct provider dashboard integrations (Google Cloud Console, DeepSeek platform). OpenRouter’s unified activity log is the single source of truth.
