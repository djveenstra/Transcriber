import AppKit
import CoreGraphics

enum IconStyle {
    case standard
    case dark
    case tinted
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let size = 1024

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: red, green: green, blue: blue, alpha: alpha)
}

func drawIcon(style: IconStyle, fileName: String) throws {
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: size * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else {
        throw CocoaError(.fileWriteUnknown)
    }

    let backgroundColors: [CGColor]
    switch style {
    case .standard:
        backgroundColors = [color(0.005, 0.012, 0.035), color(0.025, 0.075, 0.19)]
    case .dark:
        backgroundColors = [color(0.002, 0.005, 0.018), color(0.012, 0.035, 0.095)]
    case .tinted:
        backgroundColors = [color(0.015, 0.015, 0.018), color(0.05, 0.05, 0.055)]
    }

    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: backgroundColors as CFArray,
        locations: [0, 1]
    )!
    context.setFillColor(backgroundColors[0])
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: 120, y: 1024),
        end: CGPoint(x: 900, y: 0),
        options: []
    )

    let accent = style == .tinted
        ? color(0.92, 0.92, 0.94)
        : color(0.18, 0.48, 1.00)

    context.saveGState()
    context.setShadow(
        offset: .zero,
        blur: style == .tinted ? 18 : 72,
        color: style == .tinted ? color(1, 1, 1, 0.25) : color(0.18, 0.48, 1.00, 0.78)
    )
    context.setFillColor(style == .tinted ? color(0.16, 0.16, 0.18) : color(0.025, 0.10, 0.28))
    context.fillEllipse(in: CGRect(x: 192, y: 192, width: 640, height: 640))
    context.restoreGState()

    context.setStrokeColor(style == .tinted ? color(1, 1, 1, 0.28) : color(0.44, 0.65, 1.00, 0.52))
    context.setLineWidth(10)
    context.strokeEllipse(in: CGRect(x: 204, y: 204, width: 616, height: 616))

    let heights: [CGFloat] = [132, 230, 342, 474, 606, 474, 342, 230, 132]
    let barWidth: CGFloat = 38
    let gap: CGFloat = 28
    let totalWidth = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
    var x = (CGFloat(size) - totalWidth) / 2

    context.setFillColor(accent)
    for height in heights {
        let rect = CGRect(x: x, y: (CGFloat(size) - height) / 2, width: barWidth, height: height)
        let path = CGPath(
            roundedRect: rect,
            cornerWidth: barWidth / 2,
            cornerHeight: barWidth / 2,
            transform: nil
        )
        context.addPath(path)
        context.fillPath()
        x += barWidth + gap
    }

    guard let image = context.makeImage() else {
        throw CocoaError(.fileWriteUnknown)
    }
    let bitmap = NSBitmapImageRep(cgImage: image)
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try data.write(to: outputDirectory.appendingPathComponent(fileName))
}

try drawIcon(style: .standard, fileName: "AppIcon-1024.png")
try drawIcon(style: .dark, fileName: "AppIcon-1024-dark.png")
try drawIcon(style: .tinted, fileName: "AppIcon-1024-tinted.png")
