import SwiftUI

/// 3-page first-run onboarding shown once. Stores completion in UserDefaults.
struct OnboardingView: View {
    @AppStorage("onboardingCompleted") private var completed: Bool = false
    @State private var page: Int = 0
    @Environment(\.dismiss) private var dismiss

    private struct Page {
        let symbol: String
        let titleKey: LocalizedStringKey
        let bodyKey: LocalizedStringKey
        let tint: Color
    }
    private let pages: [Page] = [
        .init(symbol: "gauge.with.dots.needle.50percent",
              titleKey: "onboarding_welcome_title",
              bodyKey: "onboarding_welcome_body",
              tint: .orange),
        .init(symbol: "doc.text.magnifyingglass",
              titleKey: "onboarding_how_title",
              bodyKey: "onboarding_how_body",
              tint: .blue),
        .init(symbol: "hand.raised.fingers.spread",
              titleKey: "onboarding_limits_title",
              bodyKey: "onboarding_limits_body",
              tint: .purple)
    ]

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 16)
            Image(systemName: pages[page].symbol)
                .font(.system(size: 90, weight: .light))
                .foregroundStyle(pages[page].tint)
                .frame(height: 120)
            VStack(spacing: 12) {
                Text(pages[page].titleKey)
                    .font(.system(size: 26, weight: .bold))
                    .multilineTextAlignment(.center)
                Text(pages[page].bodyKey)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(0..<pages.count, id: \.self) { i in
                    Circle()
                        .fill(i == page ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            Button {
                if page < pages.count - 1 {
                    withAnimation { page += 1 }
                } else {
                    completed = true
                    dismiss()
                }
            } label: {
                Text(page < pages.count - 1 ? "onboarding_next" : "onboarding_done")
                    .font(.body.weight(.semibold))
                    .frame(minWidth: 140)
            }
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 40)
        .frame(width: 560, height: 480)
    }
}
