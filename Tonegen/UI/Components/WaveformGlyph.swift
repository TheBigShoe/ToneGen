// Tiny SVG-style path glyphs for each waveform, drawn with SwiftUI Canvas.
import SwiftUI

struct WaveformGlyph: View {
    let waveform: Waveform
    var color: Color = Tokens.Color.textSecondary
    var size: CGFloat = 14

    var body: some View {
        let w = size * 1.6
        let h = size
        Canvas { ctx, _ in
            var path = Path()
            buildPath(&path, w: w, h: h)
            ctx.stroke(
                path,
                with: .color(color),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            )
        }
        .frame(width: w, height: h)
    }

    private func buildPath(_ path: inout Path, w: CGFloat, h: CGFloat) {
        switch waveform {
        case .sine:
            path.move(to: CGPoint(x: 0, y: h / 2))
            path.addCurve(
                to: CGPoint(x: w / 2, y: h / 2),
                control1: CGPoint(x: w / 4, y: 0),
                control2: CGPoint(x: w / 4, y: h)
            )
            path.addCurve(
                to: CGPoint(x: w, y: h / 2),
                control1: CGPoint(x: 3 * w / 4, y: 0),
                control2: CGPoint(x: 3 * w / 4, y: h)
            )
        case .square:
            path.move(to: CGPoint(x: 0, y: h - 1))
            path.addLine(to: CGPoint(x: 0, y: 1))
            path.addLine(to: CGPoint(x: w / 2, y: 1))
            path.addLine(to: CGPoint(x: w / 2, y: h - 1))
            path.addLine(to: CGPoint(x: w, y: h - 1))
            path.addLine(to: CGPoint(x: w, y: 1))
        case .triangle:
            path.move(to: CGPoint(x: 0, y: h - 1))
            path.addLine(to: CGPoint(x: w / 4, y: 1))
            path.addLine(to: CGPoint(x: 3 * w / 4, y: h - 1))
            path.addLine(to: CGPoint(x: w, y: 1))
        case .saw:
            path.move(to: CGPoint(x: 0, y: h - 1))
            path.addLine(to: CGPoint(x: w / 2, y: 1))
            path.addLine(to: CGPoint(x: w / 2, y: h - 1))
            path.addLine(to: CGPoint(x: w, y: 1))
        case .whiteNoise, .pinkNoise:
            let xs: [CGFloat] = [0, 0.1, 0.2, 0.3, 0.45, 0.55, 0.7, 0.85, 1.0]
            let ys: [CGFloat] = [0.7, 0.2, 0.8, 0.4, 0.9, 0.1, 0.6, 0.3, 0.7]
            path.move(to: CGPoint(x: xs[0] * w, y: ys[0] * h))
            for k in 1 ..< xs.count {
                path.addLine(to: CGPoint(x: xs[k] * w, y: ys[k] * h))
            }
        }
    }
}

#if DEBUG
    #Preview {
        HStack(spacing: 20) {
            ForEach(Waveform.allCases) { wave in
                VStack(spacing: 4) {
                    WaveformGlyph(waveform: wave, color: Tokens.Color.channelL)
                    Text(wave.label)
                        .font(Tokens.Font.readoutXs)
                        .foregroundStyle(Tokens.Color.textMuted)
                }
            }
        }
        .padding()
        .background(Tokens.Color.bg)
    }
#endif
