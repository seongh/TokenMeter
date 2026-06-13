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

    @AppStorage("onboardingCompleted") private var onboardingCompleted: Bool = false

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(state: state)
        } label: {
            MenuBarLabel(state: state)
        }
        .menuBarExtraStyle(.window)

        Window("TokenMeter", id: "main") {
            MainWindow(state: state)
                .sheet(isPresented: .constant(!onboardingCompleted)) {
                    OnboardingView()
                }
        }
        .defaultSize(width: 960, height: 720)

        Window("Welcome", id: "onboarding") {
            OnboardingView()
        }
        .windowResizability(.contentSize)
    }
}
