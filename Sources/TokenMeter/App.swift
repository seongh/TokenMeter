import SwiftUI

@main
struct TokenMeterApp: App {
    // Focus is local-only — Claude Code logs. Admin-API adapters are kept in
    // the codebase (Anthropic/OpenAI) for future use but are not wired into
    // the default scene because admin API keys are uncommon and the Console
    // already shows the same numbers.
    @StateObject private var state = AppState(providers: [
        ClaudeCodeProvider()
    ])

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(state: state)
        } label: {
            MenuBarLabel(state: state)
        }
        .menuBarExtraStyle(.window)

        Window("TokenMeter", id: "main") {
            MainWindow(state: state)
        }
        .defaultSize(width: 960, height: 700)
    }
}
