import AppKit

// Draws the LimitHUD app icon: dark squircle + a 270° "remaining quota" gauge.
// Usage: swift icongen.swift <output.iconset dir>

func deg(_ d: CGFloat) -> CGFloat { d * .pi / 180 }

func draw(_ ctx: CGContext, _ S: CGFloat) {
    let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
        CGColor(colorSpace: sRGB, components: [r, g, b, a])!
    }

    // transparent canvas
    ctx.clear(CGRect(x: 0, y: 0, width: S, height: S))

    // squircle background
    let margin = S * 0.085
    let rect = CGRect(x: margin, y: margin, width: S - 2*margin, height: S - 2*margin)
    let radius = rect.width * 0.2237
    let squircle = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    ctx.saveGState()
    ctx.addPath(squircle); ctx.clip()
    let grad = CGGradient(colorsSpace: sRGB,
                          colors: [c(0.105, 0.105, 0.115), c(0.045, 0.045, 0.055)] as CFArray,
                          locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: S), end: CGPoint(x: 0, y: 0), options: [])
    // soft top highlight
    let hi = CGGradient(colorsSpace: sRGB,
                        colors: [c(1, 1, 1, 0.06), c(1, 1, 1, 0)] as CFArray,
                        locations: [0, 1])!
    ctx.drawLinearGradient(hi, start: CGPoint(x: 0, y: S), end: CGPoint(x: 0, y: S * 0.55), options: [])
    ctx.restoreGState()

    // hairline border
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.setStrokeColor(c(1, 1, 1, 0.09))
    ctx.setLineWidth(max(1, S * 0.0045))
    ctx.strokePath()
    ctx.restoreGState()

    // gauge geometry
    let center = CGPoint(x: S/2, y: S/2)
    let r = rect.width * 0.300
    let lw = rect.width * 0.090
    ctx.setLineCap(.round)
    ctx.setLineWidth(lw)

    // track (270°, gap at bottom)
    ctx.setStrokeColor(c(1, 1, 1, 0.12))
    ctx.addArc(center: center, radius: r, startAngle: deg(-45), endAngle: deg(225), clockwise: false)
    ctx.strokePath()

    // remaining fill (from left, over the top)
    let remaining: CGFloat = 0.72
    let endA = deg(225 - remaining * 270)
    let green = c(0.20, 0.79, 0.51) // #34C982
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: S * 0.025, color: c(0.20, 0.79, 0.51, 0.55))
    ctx.setStrokeColor(green)
    ctx.addArc(center: center, radius: r, startAngle: deg(225), endAngle: endA, clockwise: true)
    ctx.strokePath()
    ctx.restoreGState()

    // marker dot at the fill end
    let dot = CGPoint(x: center.x + r * cos(endA), y: center.y + r * sin(endA))
    ctx.setFillColor(c(0.96, 0.96, 0.96))
    let dr = lw * 0.30
    ctx.fillEllipse(in: CGRect(x: dot.x - dr, y: dot.y - dr, width: dr*2, height: dr*2))

    // center: a compact "%" mark in mono
    let pct = "%" as NSString
    let fontSize = rect.width * 0.30
    let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(srgbRed: 0.96, green: 0.96, blue: 0.97, alpha: 1)
    ]
    let textSize = pct.size(withAttributes: attrs)
    let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsCtx
    pct.draw(at: CGPoint(x: center.x - textSize.width/2, y: center.y - textSize.height/2),
             withAttributes: attrs)
    NSGraphicsContext.restoreGraphicsState()
}

func render(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                              colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let nsCtx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsCtx
    draw(nsCtx.cgContext, CGFloat(size))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let sizes: [(String, Int)] = [
    ("icon_16x16",     16),  ("icon_16x16@2x",   32),
    ("icon_32x32",     32),  ("icon_32x32@2x",   64),
    ("icon_128x128",  128),  ("icon_128x128@2x",256),
    ("icon_256x256",  256),  ("icon_256x256@2x",512),
    ("icon_512x512",  512),  ("icon_512x512@2x",1024),
]
for (name, px) in sizes {
    let data = render(size: px)
    try! data.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
}
print("wrote \(sizes.count) icon pngs to \(outDir)")
