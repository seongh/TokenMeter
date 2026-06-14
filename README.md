# TokenMeter

**A macOS menu-bar app for real-time Claude Code usage tracking.**

TokenMeter reads your local Claude Code logs and shows — in your menu bar, in plain language — how much you've used, how fast you're burning, and when your current 5-hour session resets. No guessing, no fake numbers.

We focus on **Claude only**, on purpose. ChatGPT, Cursor, Windsurf, Gemini, and the Claude.ai web/desktop apps don't expose per-message token data, so we refuse to fake it. Honesty over false coverage.

---

## What you see

**Menu bar (one glance):**
- `⏱ 1시간 50분 남음` — time until your current 5-hour session resets
- `⏱ 오늘 ≈ 책 1,100권` — when no session is active, today's volume in book-equivalents
- Gauge icon color shifts from green → amber → red as you approach your budget

**Drop-down panel:**
- Status word ("여유 있음" / "Plenty of room") + human-language explanation
- Active session progress (tokens + messages)
- Today + this week summaries with book-count comparisons
- 7-day mini chart

**Dashboard window:**
- Hero card with status and three big numbers (tokens, messages, pace vs. baseline)
- Daily stacked bars grouped by model / project / token kind
- **Model efficiency** — heuristic estimate of how many Opus messages could have run on Sonnet
- **MCP server tools** — web_search / web_fetch counts
- **Top projects** — which Claude Code workspaces ate the most tokens
- **Top 10 most expensive messages** — drill-down for debugging
- **Recent session blocks** — 5-hour windows with model + cost
- CSV / JSON export
- Budget / notification / launch-at-login settings
- Korean & English UI (follows system language)

## Honest data sources

| Source | Tracked? | Why |
|---|---|---|
| **Claude Code (CLI)** | ✅ exact | Local JSONL contains every `usage` block from the API response |
| **Anthropic Admin API** (optional) | ✅ exact | `/v1/organizations/usage_report/messages` — org owners only |
| Claude.ai web / desktop | ❌ | Anthropic does not publish token data for subscription users |
| ChatGPT Plus / Pro | ❌ | OpenAI does not publish token data for ChatGPT |
| Cursor / Windsurf / Codeium | ❌ | Vendors do not publish per-message token counts |
| Gemini, Perplexity, others | ❌ | Same |

We track what we can verify. Anything else is honest blank.

## Architecture

```
Sources/TokenMeter/
├── App.swift                       # MenuBarExtra + Window + Onboarding scenes
├── AppState.swift                  # @MainActor central store + status + analysis
├── Model/
│   ├── UsageRecord.swift           # One token-accounting event
│   ├── Provider.swift              # claudeCode + anthropicAPI (only)
│   ├── ModelCatalog.swift          # Claude Opus / Sonnet / Haiku 4.x pricing
│   ├── ProviderStatus.swift        # Sync state
│   ├── UsageStatus.swift           # StatusLevel: relaxed / watch / critical / idle
│   └── Aggregates.swift            # Daily / project / session bucketing
├── Providers/
│   ├── UsageProvider.swift         # Protocol + ProviderError + TestResult
│   ├── ClaudeCodeProvider.swift    # JSONL parser + FSEvents live stream
│   └── AnthropicAPIProvider.swift  # Optional /v1/organizations/usage_report polling
├── Storage/
│   ├── StateStore.swift            # JSON cache for instant-start
│   ├── ClaudeFolderAccess.swift    # Sandbox-aware folder grant + bookmark
│   ├── Keychain.swift              # API key storage
│   └── Exporter.swift              # CSV / JSON serializer
├── Watcher/
│   ├── ClaudeCodeWatcher.swift     # FSEvents wrapper
│   ├── SessionNotifier.swift       # Budget + burn-rate alerts
│   └── LaunchAtLogin.swift         # SMAppService
├── UI/
│   ├── MenuBarContent.swift        # Drop-down panel
│   ├── MainWindow.swift            # Dashboard
│   ├── HeroCard.swift              # Top-of-dashboard status block
│   ├── OnboardingView.swift        # First-run 3-page sheet
│   └── Formatting.swift            # Locale-aware tokens / time / cost
└── Resources/
    ├── en.lproj/Localizable.strings
    └── ko.lproj/Localizable.strings
```

## Build & run

```bash
# Requires Xcode 15+ (macOS 14+, Swift 6 toolchain)
./Scripts/build-app.sh                  # sandboxed, ad-hoc signed (App Store style)
./Scripts/build-app.sh --no-sandbox     # local dev, reads ~/.claude/projects directly
open TokenMeter.app
```

The build script:
1. `swift build -c release`
2. Generates `Assets/AppIcon.icns` from `Assets/icon_1024.png`
3. Assembles `TokenMeter.app` with Info.plist, icon, and `.lproj` localizations
4. Ad-hoc code signs (with `TokenMeter.entitlements` when sandboxed)

### Tests + parser smoke test

```bash
swift test                  # unit tests for parser, aggregator, status, store
swift Scripts/smoke.swift   # parse your real ~/.claude/projects and print totals
```

## Settings

All in the dashboard (menu bar → **대시보드 열기**):

- **Session token budget** / **Weekly token budget** / **Session message budget** — targets used to color the progress bars. Not Anthropic's actual limits (those aren't public).
- **Notify at 80% / 95%** — macOS notification when you cross your own session budget.
- **Burn-rate alert** — fires once per session when your pace is ≥ 1.5× your 7-day baseline.
- **Launch at login** — SMAppService registration.

## Privacy

- All parsing happens locally.
- The only network calls are to `api.anthropic.com`, and only if you explicitly enter an Anthropic Admin API key.
- Cache: `~/Library/Application Support/TokenMeter/state.json` (or `~/Library/Containers/com.seongho.tokenmeter/Data/...` in sandboxed builds).
- Keychain service id: `com.seongho.tokenmeter`.

## Mac App Store submission

The codebase is set up for sandboxed distribution. The build script signs with `TokenMeter.entitlements` (App Sandbox + network client + user-selected read-only files + app-scope bookmarks), and the runtime asks the user via `NSOpenPanel` for read access to the Claude logs folder.

What's already done in code:
- `TokenMeter.entitlements` — sandbox, network.client, files.user-selected.read-only, files.bookmarks.app-scope
- `ClaudeFolderAccess.swift` — detects sandbox via `NSHomeDirectory()`, presents an open panel, stores a security-scoped bookmark
- `MainWindow.folderAccessCardIfNeeded` — first-run UI when no bookmark is saved
- Build script signs with `--entitlements TokenMeter.entitlements -o runtime`

What you must do (paid / account-bound):

1. **Enroll in the Apple Developer Program** ($99/year) at developer.apple.com
2. **Reserve `com.seongho.tokenmeter`** in App Store Connect (or change `CFBundleIdentifier`)
3. **Create signing assets**: Mac App Distribution cert + Mac Installer Distribution cert + provisioning profile
4. **Replace ad-hoc signing** in `Scripts/build-app.sh`: `--sign -` → `--sign "3rd Party Mac Developer Application: Your Name (TEAMID)"`
5. **Build the installer**:
   ```bash
   productbuild --component TokenMeter.app /Applications \
       --sign "3rd Party Mac Developer Installer: Your Name (TEAMID)" \
       TokenMeter.pkg
   ```
6. **Upload via Transporter** to App Store Connect
7. **Fill in metadata**: description, screenshots, privacy nutrition labels (we collect zero analytics — only outbound network is the optional Admin API call, gated on the user entering their own key)
8. **Submit for review** (1–3 days)

### Review notes worth including

- Menu-bar-only (`LSUIElement = true`) is intentional — the dashboard Window scene satisfies the "preferences window" requirement
- We deliberately scope to Claude usage; we never read other tools' private state
- Anthropic Max plan limits are not public, so the session bar shows a user-defined target with explicit disclosure

## License

MIT.
