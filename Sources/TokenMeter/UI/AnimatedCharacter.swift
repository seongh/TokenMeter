import SwiftUI

/// Animated emoji used in the menu bar. Motion amplitude is intentionally
/// small (1–3pt) so the character feels alive without being distracting —
/// macOS HIG asks for restraint in menu bar UI.
///
/// Each Motion conveys what kind of intensity the user is in:
///   - walking/running: vertical bob + tiny forward lean
///   - hulk: scale pulse + micro shake (근육이 움찔)
///   - superman: smooth horizontal float (비행)
///   - rocket: vertical lift + side jitter (이륙 진동)
///   - asleep: completely still
struct AnimatedCharacter: View {
    enum Motion {
        case asleep
        case walking
        case running
        case sprinting
        case hulk
        case superman
        case rocket
    }

    let emoji: String
    let motion: Motion
    let size: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: motion == .asleep)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Text(emoji)
                .font(.system(size: size))
                .offset(x: offsetX(t), y: offsetY(t))
                .scaleEffect(scale(t))
                .rotationEffect(.degrees(rotation(t)))
        }
        .frame(width: size + 6, height: size + 4)
    }

    // MARK: - Per-axis motion

    private func offsetY(_ t: TimeInterval) -> CGFloat {
        switch motion {
        case .asleep:    return 0
        case .walking:   return sin(t * 3) * 1.0
        case .running:   return -abs(sin(t * 7)) * 2.0       // small hops
        case .sprinting: return -abs(sin(t * 10)) * 2.5
        case .hulk:      return sin(t * 4) * 0.6
        case .superman:  return sin(t * 2) * 1.5             // smooth float
        case .rocket:    return -abs(sin(t * 8)) * 2.5 - 0.5 // rises with bounce
        }
    }

    private func offsetX(_ t: TimeInterval) -> CGFloat {
        switch motion {
        case .superman: return sin(t * 2) * 3.0              // side-to-side flight
        case .rocket:   return cos(t * 11) * 0.7             // tiny lateral jitter
        default:        return 0
        }
    }

    private func scale(_ t: TimeInterval) -> CGFloat {
        switch motion {
        case .hulk:   return 1.0 + abs(sin(t * 4)) * 0.12    // muscle pulse
        case .rocket: return 1.0 + sin(t * 6) * 0.05
        default:      return 1.0
        }
    }

    private func rotation(_ t: TimeInterval) -> Double {
        switch motion {
        case .running:   return sin(t * 7) * 5               // forward/back tilt
        case .sprinting: return sin(t * 10) * 8
        case .hulk:      return sin(t * 8) * 2               // tiny shake
        case .superman:  return sin(t * 2) * 4               // banking turn
        default:         return 0
        }
    }
}
