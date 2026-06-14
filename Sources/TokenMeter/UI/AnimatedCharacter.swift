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
        // Stable frame so motion never reshapes the menu bar layout, but
        // large enough that ±6pt motion + 1.2× scale stay inside the box.
        Text(emoji)
            .font(.system(size: size))
            .fixedSize()
            .modifier(EmojiMotion(motion: motion))
            .frame(width: size + 14, height: size + 8, alignment: .center)
    }

}

/// Reads time from a single TimelineView and applies motion transforms.
/// Keeping this as a separate ViewModifier means the AnimatedCharacter
/// outer view has a stable, predictable layout footprint — its frame is
/// computed once and motion only affects the rendered emoji inside.
struct EmojiMotion: ViewModifier {
    let motion: AnimatedCharacter.Motion

    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0,
                                paused: motion == .asleep)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            content
                .offset(x: offsetX(t), y: offsetY(t))
                .scaleEffect(scale(t))
                .rotationEffect(.degrees(rotation(t)))
        }
    }

    // MARK: - Per-axis motion

    private func offsetY(_ t: TimeInterval) -> CGFloat {
        switch motion {
        case .asleep:    return 0
        case .walking:   return sin(t * 3) * 3.0             // gentle stroll
        case .running:   return -abs(sin(t * 8)) * 4.0       // distinct hops
        case .sprinting: return -abs(sin(t * 11)) * 4.5
        case .hulk:      return sin(t * 5) * 1.5
        case .superman:  return sin(t * 2.5) * 3.0           // smooth float
        case .rocket:    return -abs(sin(t * 9)) * 5.0 - 1.0 // rises hard
        }
    }

    private func offsetX(_ t: TimeInterval) -> CGFloat {
        switch motion {
        case .superman: return sin(t * 2) * 6.0              // strong side-to-side flight
        case .rocket:   return cos(t * 14) * 1.5             // shake from takeoff
        default:        return 0
        }
    }

    private func scale(_ t: TimeInterval) -> CGFloat {
        switch motion {
        case .hulk:      return 1.0 + abs(sin(t * 5)) * 0.20 // muscle pulse, big
        case .rocket:    return 1.0 + sin(t * 7) * 0.08
        case .superman:  return 1.0 + abs(sin(t * 2)) * 0.05 // breath of speed
        default:         return 1.0
        }
    }

    private func rotation(_ t: TimeInterval) -> Double {
        switch motion {
        case .running:   return sin(t * 8) * 10              // visible lean
        case .sprinting: return sin(t * 11) * 14
        case .hulk:      return sin(t * 10) * 3              // visible shake
        case .superman:  return sin(t * 2) * 8               // banking turn
        case .rocket:    return cos(t * 14) * 4              // shaking
        default:         return 0
        }
    }
}
