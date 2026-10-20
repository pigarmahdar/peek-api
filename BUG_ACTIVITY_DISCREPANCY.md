# Bug Report: Discrepancy Between OpenRouter Activity Dashboard and Menu Bar UI

**Date:** 2026-10-20  
**Severity:** Medium (Data Accuracy / User Perception)  
**Status:** Resolved  
**Components:** `OpenRouterClient.swift`, `SpendEngine.swift`, Timezone Handling, API Ingestion  

---

## 1. Summary

A spend discrepancy was observed between the OpenRouter web dashboard and the `peek-api` menu bar UI:
* **OpenRouter Web UI ("Explore" Tab):** Shows **$0.202** inference spend recorded for today (Oct 20) under `GMT+8` (SGT), across *Muse Spark 1.3 Contributor* ($0.195) and *MiMo-V2.5* ($0.00709).
* **`peek-api` Menu Bar UI:** Displays **$0.00 today** and *"No inference activity recorded today"*, despite successfully fetching credit balance ($5.27 left) and month-to-date spend ($10.90).

---

## 2. Root Cause Analysis

Investigation revealed two contributing factors:

### Factor A: Hardcoded UTC Timezone vs Local SGT (GMT+8)
In `Sources/PeekAPICore/Services/OpenRouterClient.swift` (lines 140–144):
```swift
let formatter = DateFormatter()
formatter.timeZone = TimeZone(secondsFromGMT: 0) // <-- Hardcoded to UTC (GMT+0)
formatter.dateFormat = "yyyy-MM-dd"
let todayString = formatter.string(from: now)
```
* The user's system and OpenRouter dashboard are set to **SGT (GMT+8)**.
* `peek-api` determines `todayString` strictly against UTC (`secondsFromGMT: 0`).
* Between 00:00 and 08:00 SGT, the local date is Day $N$ while UTC is still Day $N-1$, causing a complete mismatch.
* The app ignores the device's `TimeZone.current` and OpenRouter's dashboard timezone selection.

### Factor B: Endpoint Data Latency (`/api/v1/activity` vs `/api/v1/analytics/query`)
* `peek-api` called `GET https://openrouter.ai/api/v1/activity`.
* Per OpenRouter documentation, `/api/v1/activity` provides historical aggregation grouped by completed UTC days with batch processing lag. In-flight or newly incurred inference on the current day is not populated immediately.
* OpenRouter's dashboard "Explore" tab uses the real-time analytics subsystem (`POST https://openrouter.ai/api/v1/analytics/query`), which evaluates granular data up to the current minute with customizable time ranges and timezones.

---

## 3. Resolution

1. **Real-time Querying via `POST /api/v1/analytics/query`:**
   - Implemented `fetchRealtimeTodaySpend(now:timeZone:)` targeting `https://openrouter.ai/api/v1/analytics/query`.
   - Queries `total_usage` grouped by `["model", "provider"]` over `[startOfDay, now]`.
   - `startOfDay` is computed using `Calendar(identifier: .gregorian)` with `timeZone` (defaulting to `TimeZone.current` / SGT).
2. **De-duplication & Merging:**
   - `processWithRealtime` integrates real-time today items with historical month-to-date items (excluding today's date from historical items so no double-counting occurs).
   - If the analytics query fails, the client gracefully falls back to `processActivityItems(items, relativeTo: now, timeZone: timeZone)`.
3. **Verification:**
   - Added unit test `testRealtimeAnalyticsProcessingAndMerging` in `PeekAPICheck` verifying SGT date alignment, BYOK detection, and real-time today + month spend merging.
