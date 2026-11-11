// Subtle static film-grain texture — 4% opacity white dots over the background.
import SwiftUI

struct GrainOverlay: View {
    var body: some View {
        Canvas { ctx, size in
            // Deterministic LCG so the grain is the same every render.
            var seed: UInt32 = 0xDEAD_BEEF
            func next() -> CGFloat {
                seed = seed &* 1_664_525 &+ 1_013_904_223
                return CGFloat(seed >> 8) / CGFloat(0xFF_FFFF)
            }

            let dotCount = Int(size.width * size.height * 0.08)
            for _ in 0 ..< dotCount {
                let x = next() * size.width
                let y = next() * size.height
                let alpha = 0.02 + next() * 0.04
                ctx.fill(
                    Path(ellipseIn: CGRect(x: x, y: y, width: 1, height: 1)),
                    with: .color(.white.opacity(alpha))
                )
            }
        }
        .allowsHitTesting(false)
    }
}
