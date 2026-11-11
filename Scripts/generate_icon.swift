// Generates the Tonegen app icon: oscilloscope sine wave, amber on near-black.
// Run with: swift Scripts/generate_icon.swift
import CoreGraphics
import Foundation
import ImageIO

let size = 1024
let cs = CGColorSpaceCreateDeviceRGB()
let bmp = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: size * 4,
    space: cs,
    bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little
        .rawValue
)!

// CoreGraphics origin is bottom-left; we'll draw as if top-left by flipping Y when needed.
let w = CGFloat(size)
let h = CGFloat(size)

// Background
bmp.setFillColor(CGColor(colorSpace: cs, components: [0.039, 0.035, 0.031, 1])!)
bmp.fill(CGRect(x: 0, y: 0, width: w, height: h))

/// Subtle scope grid
let gridColor = CGColor(colorSpace: cs, components: [0.122, 0.110, 0.098, 0.55])!
bmp.setStrokeColor(gridColor)
bmp.setLineWidth(1.5)
for col in 1 ..< 8 {
    let x = w / 8 * CGFloat(col)
    bmp.move(to: CGPoint(x: x, y: 0))
    bmp.addLine(to: CGPoint(x: x, y: h))
    bmp.strokePath()
}

for row in 1 ..< 4 {
    let y = h / 4 * CGFloat(row)
    bmp.move(to: CGPoint(x: 0, y: y))
    bmp.addLine(to: CGPoint(x: w, y: y))
    bmp.strokePath()
}

/// Center axis slightly brighter
let axisColor = CGColor(colorSpace: cs, components: [0.165, 0.145, 0.133, 0.7])!
bmp.setStrokeColor(axisColor)
bmp.setLineWidth(1.5)
bmp.move(to: CGPoint(x: 0, y: h / 2))
bmp.addLine(to: CGPoint(x: w, y: h / 2))
bmp.strokePath()

// Build the sine wave path — 2.5 cycles, centered, large amplitude
let steps = 1024
let cycles = 2.5
let amplitude = h * 0.30
let centerY = h / 2

func sinePath() -> CGPath {
    let path = CGMutablePath()
    for i in 0 ... steps {
        let t = CGFloat(i) / CGFloat(steps)
        let x = t * w
        let y = centerY + amplitude * sin(t * CGFloat(cycles) * 2 * .pi)
        if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
        else { path.addLine(to: CGPoint(x: x, y: y)) }
    }
    return path
}

let amber = CGColor(colorSpace: cs, components: [1.0, 0.694, 0.278, 1])!

/// Outer glow passes (widest first so core overwrites)
let glowPasses: [(width: CGFloat, alpha: CGFloat)] = [
    (60, 0.04), (40, 0.07), (24, 0.12), (14, 0.22), (8, 0.40),
]
for pass in glowPasses {
    let glowColor = CGColor(colorSpace: cs, components: [1.0, 0.694, 0.278, pass.alpha])!
    bmp.setStrokeColor(glowColor)
    bmp.setLineWidth(pass.width)
    bmp.setLineCap(.round)
    bmp.setLineJoin(.round)
    bmp.addPath(sinePath())
    bmp.strokePath()
}

// Core wave — crisp and bright
bmp.setStrokeColor(amber)
bmp.setLineWidth(5)
bmp.setLineCap(.round)
bmp.setLineJoin(.round)
bmp.addPath(sinePath())
bmp.strokePath()

// Write PNG
guard let img = bmp.makeImage() else { fatalError("makeImage failed") }

let outURL = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "AppIcon.png")

guard let dest = CGImageDestinationCreateWithURL(outURL as CFURL, "public.png" as CFString, 1, nil)
else { fatalError("Could not create image destination") }
CGImageDestinationAddImage(dest, img, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("Failed to write PNG") }
print("Icon written to \(outURL.path)")
