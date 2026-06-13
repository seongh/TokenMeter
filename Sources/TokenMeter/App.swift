import SwiftUI

@main
struct TokenMeterApp: App {
    @StateObject private var state = AppState(providers: [
        ClaudeCodeProvider(),
        AnthropicAPIProvider(),
        OpenAIAPIProvider()
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
