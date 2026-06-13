# TokenMeter

A macOS menu-bar app that tracks AI token usage across Claude Code, the Anthropic API, and the OpenAI API — in real time, with daily/weekly breakdowns, project attribution, MCP tool counts, and CSV/JSON export.

Built because Anthropic's Max plan doesn't expose a "tokens remaining" number; this app reconstructs the picture from the data that *is* available locally and via the official admin APIs.

---

## What it does

- **Reads `~/.claude/projects/*.jsonl`** — every Claude Code message's exact token counts (input / cache write / cache read / output) and model id, parsed incrementally with FSEvents file watching.
- **Polls the Anthropic Admin API** — daily usage buckets, when you provide an admin key (`sk-ant-admin-…`).
- **Polls the OpenAI Admin API** — same shape, with an OpenAI admin key (`sk-admin-…`).
- **Aggregates everything** — by day, week, model, provider, project, and 5-hour session block.
- **Surfaces MCP server-side tool usage** — `web_search` and `web_fetch` call counts from the `server_tool_use` field.
- **Notifies at 80% / 95%** of your configured session token budget.
- **Detects other AI tools** (Cursor / Windsurf / Codeium) installed on the Mac — but only reads directory existence, never their private state.
- **Exports** the full record set as CSV or JSON.

## Honest limitations

| Source | Tracked? | Why |
|---|---|---|
| Claude Code (CLI) | ✅ exact | Local JSONL contains every `usage` block |
| Anthropic API (admin key) | ✅ exact | Official `/v1/organizations/usage_report/messages` endpoint |
| OpenAI API (admin key) | ✅ exact | Official `/v1/organization/usage/completions` endpoint |
| **Claude Max / Pro (web + desktop)** | ❌ | Anthropic does not publish a token counter for subscription plans. The 5-hour session bar in the app shows your *measured* Claude Code consumption against a budget you set, not the real plan ceiling. |
| ChatGPT Plus subscription | ❌ | OpenAI does not publish a token counter for ChatGPT subscriptions. |
| Cursor / Windsurf / Codeium | ❌ data, ✅ presence | These tools don't expose per-message token counts. We detect that they're installed and say so honestly. |

## Architecture

```
Sources/TokenMeter/
├── App.swift                       # MenuBarExtra + Window scene
├── AppState.swift                  # @MainActor central store
├── Model/
│   ├── UsageRecord.swift           # One token-accounting event
│   ├── Provider.swift              # claudeCode / anthropicAPI / openAIAPI / …
│   ├── ModelCatalog.swift          # Pricing + context windows for known models
│   ├── ProviderStatus.swift        # Sync state per provider
│   └── Aggregates.swift            # Daily / project / session bucketing
├── Providers/
│   ├── UsageProvider.swift         # Protocol + ProviderError + TestResult
│   ├── ClaudeCodeProvider.swift    # JSONL parser + FSEvents-driven live stream
│   ├── AnthropicAPIProvider.swift  # Real /v1/organizations/usage_report/messages
│   ├── OpenAIAPIProvider.swift     # Real /v1/organization/usage/completions
│   └── InstallProbe.swift          # Read-only directory probe
├── Storage/
│   ├── StateStore.swift            # JSON cache for instant-start
│   ├── Keychain.swift              # API key storage
│   └── Exporter.swift              # CSV / JSON serializer
├── Watcher/
│   ├── ClaudeCodeWatcher.swift     # FSEvents wrapper
│   ├── SessionNotifier.swift       # UserNotifications threshold alerts
│   └── LaunchAtLogin.swift         # SMAppService wrapper
└── UI/
    ├── MenuBarContent.swift        # Compact dropdown
    ├── MainWindow.swift            # Charts + tables + settings
    └── Formatting.swift            # Token / cost / time helpers
```

## Build & run

```bash
# Requires Xcode 15+ (macOS 14+, Swift 6 toolchain)
./Scripts/build-app.sh        # release build + .app bundle + ad-hoc code sign
open TokenMeter.app
```

The build script:
1. `swift build -c release`
2. Generates `Assets/AppIcon.icns` from `Assets/icon_1024.png` via `sips` + `iconutil`
3. Assembles `TokenMeter.app` with `Info.plist` and icon
4. Ad-hoc code signs (`codesign --force --deep --sign -`)

> Real notarization requires an Apple Developer ID and is intentionally out of scope. Ad-hoc signing is enough to launch the app on the build machine without Gatekeeper friction.

### Regenerate the icon

```bash
swift Scripts/make-icon.swift   # writes Assets/icon_1024.png
./Scripts/build-app.sh          # rebuilds .icns from the new PNG
```

### Smoke test the parser against your real logs

```bash
swift Scripts/smoke.swift       # prints token totals by model / day / project
```

### Run the unit tests

```bash
swift test
```

Current coverage: parser correctness (Claude Code JSONL), aggregation (daily / by-project / by-model / session windowing), state-store round-trip, install detection, provider-status formatting.

## Settings

All settings live in the dashboard (open via the menu bar drop-down → **Open dashboard**):

- **API keys** — Anthropic admin key, OpenAI admin key. Stored in the macOS Keychain. **Test** button does a real round-trip and shows the result inline.
- **Session token budget** / **Weekly token budget** — targets used to render the progress bars (since true plan ceilings aren't exposed).
- **Notify at 80% / 95%** — toggles macOS notifications for session thresholds.
- **Launch at login** — SMAppService registration.

## Data & privacy

- All parsing happens locally; the only network requests are to `api.anthropic.com` and `api.openai.com`, gated on you explicitly entering admin keys.
- Cache location: `~/Library/Application Support/TokenMeter/state.json`.
- Keychain service id: `com.seongho.tokenmeter`.

## License

MIT.
