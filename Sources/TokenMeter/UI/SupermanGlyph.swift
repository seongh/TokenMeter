import SwiftUI

/// Custom side-view Superman glyph drawn with SwiftUI Canvas.
/// Emoji can't show a side-view flying pose with a rippling cape, so we
/// hand-draw a simple silhouette and animate the cape's trailing edge with
/// a phase-shifted sine wave per vertex.
///
/// Geometry is laid out on a 32×16 logical canvas and scaled to fit the
/// requested size so it stays crisp on Retina displays.
struct SupermanGlyph: View {
    let size: CGFloat              // emoji-equivalent point size

    private let logicalWidth: CGFloat = 32
    private let logicalHeight: CGFloat = 16

    private var renderSize: CGSize {
        // Slightly wider than tall so the outstretched arm + cape fit.
        CGSize(width: size * 2.0, height: size * 1.2)
    }

    private let bodyColor = Color(red: 0.15, green: 0.35, blue: 0.85)
    private let capeColor = Color(red: 0.85, green: 0.15, blue: 0.15)
    private let accent    = Color(red: 0.97, green: 0.85, blue: 0.18)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, canvasSize in
                let s = min(canvasSize.width / logicalWidth,
                            canvasSize.height / logicalHeight)
                // Center the logical 32×16 box inside the canvas.
                let dx = (canvasSize.width - logicalWidth * s) / 2
                let dy = (canvasSize.height - logicalHeight * s) / 2
                ctx.translateBy(x: dx, y: dy)
                ctx.scaleBy(x: s, y: s)

                // Add a gentle whole-body float so flying feels continuous.
                let bodyBob = CGFloat(sin(t * 2.0) * 0.4)
                ctx.translateBy(x: 0, y: bodyBob)

                drawCape(ctx, time: t)
                drawBody(ctx)
            }
        }
        .frame(width: renderSize.width, height: renderSize.height)
    }

    // MARK: - Body (drawn after cape so it sits in front)

    private func drawBody(_ ctx: GraphicsContext) {
        // Horizontal flying torso: head at right, legs at left, arm reaching forward.
        // Layout (logical px, origin top-left):
        //
        //   0       8        16       24       32
        //   ┌───────────────────────────────────┐
        //   │   cape      torso      → arm     │  ← y 4-12 is the body band
        //   └───────────────────────────────────┘

        // Trailing leg
        var legPath = Path()
        legPath.addRoundedRect(in: CGRect(x: 7.5, y: 9.5, width: 5, height: 2.5),
                               cornerSize: CGSize(width: 1, height: 1))
        ctx.fill(legPath, with: .color(bodyColor))

        // Torso (rounded rectangle)
        var torso = Path()
        torso.addRoundedRect(in: CGRect(x: 10, y: 6, width: 12, height: 4.5),
                             cornerSize: CGSize(width: 2, height: 2))
        ctx.fill(torso, with: .color(bodyColor))

        // S-shield on chest (small yellow diamond)
        var shield = Path()
        let cx: CGFloat = 16, cy: CGFloat = 8.2
        shield.move(to: CGPoint(x: cx, y: cy - 1.0))
        shield.addLine(to: CGPoint(x: cx + 0.9, y: cy))
        shield.addLine(to: CGPoint(x: cx, y: cy + 1.0))
        shield.addLine(to: CGPoint(x: cx - 0.9, y: cy))
        shield.closeSubpath()
        ctx.fill(shield, with: .color(accent))

        // Outstretched arm (forward / right)
        var arm = Path()
        arm.addRoundedRect(in: CGRect(x: 22, y: 7, width: 7, height: 2.3),
                           cornerSize: CGSize(width: 1, height: 1))
        ctx.fill(arm, with: .color(bodyColor))

        // Fist at the tip of the arm
        var fist = Path()
        fist.addEllipse(in: CGRect(x: 28, y: 6.6, width: 2.6, height: 2.8))
        ctx.fill(fist, with: .color(bodyColor))

        // Head — slightly raised so it reads as "looking forward"
        var head = Path()
        head.addEllipse(in: CGRect(x: 20.5, y: 3.5, width: 4.5, height: 4.5))
        ctx.fill(head, with: .color(accent.opacity(0.95)))   // skin tone proxy

        // Hair (small dark cap on top of head, side profile)
        var hair = Path()
        hair.addEllipse(in: CGRect(x: 20.3, y: 3.2, width: 4.2, height: 2.0))
        ctx.fill(hair, with: .color(Color(red: 0.10, green: 0.10, blue: 0.18)))
    }

    // MARK: - Cape (drawn first so it trails behind)

    private func drawCape(_ ctx: GraphicsContext, time: TimeInterval) {
        // The cape attaches at the shoulder/back area and trails left.
        // Each vertex on the trailing edge gets its own phase-shifted sine
        // wave amplitude that grows with distance — so the tip ripples
        // the most, like real cloth in flight.
        let segments = 16
        let attachTopX: CGFloat = 11
        let attachTopY: CGFloat = 6
        let attachBotX: CGFloat = 11
        let attachBotY: CGFloat = 10.5
        let trailLength: CGFloat = 10

        var top = Path()
        top.move(to: CGPoint(x: attachTopX, y: attachTopY))

        // Collect the top edge points so the bottom edge can mirror them
        // with an opposite phase, giving the cape internal wave structure.
        var topEdge: [CGPoint] = [CGPoint(x: attachTopX, y: attachTopY)]
        for i in 1...segments {
            let progress = CGFloat(i) / CGFloat(segments)
            let x = attachTopX - progress * trailLength
            let wave = sin(time * 8 + Double(i) * 0.6) * Double(progress) * 1.8
            let y = attachTopY - 0.4 + CGFloat(wave)
            let pt = CGPoint(x: x, y: y)
            top.addLine(to: pt)
            topEdge.append(pt)
        }

        // Connect to the bottom trailing tip and walk back along the bottom edge.
        for i in stride(from: segments, through: 1, by: -1) {
            let progress = CGFloat(i) / CGFloat(segments)
            let x = attachBotX - progress * trailLength
            let wave = sin(time * 8 + Double(i) * 0.6 + .pi * 0.6) * Double(progress) * 1.8
            let y = attachBotY + 0.4 + CGFloat(wave)
            top.addLine(to: CGPoint(x: x, y: y))
        }
        top.addLine(to: CGPoint(x: attachBotX, y: attachBotY))
        top.closeSubpath()

        ctx.fill(top, with: .color(capeColor))

        // Subtle darker fold near the shoulders for depth.
        var fold = Path()
        fold.addRoundedRect(in: CGRect(x: 9.5, y: 6.5, width: 3, height: 4),
                            cornerSize: CGSize(width: 1.5, height: 1.5))
        ctx.fill(fold, with: .color(capeColor.opacity(0.65)))
    }
}
