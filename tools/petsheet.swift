import AppKit

// Renders the pet sheet straight from the PRODUCTION renderer (PixelPet.swift),
// so the preview always matches the app.
// Build & run:
//   swiftc -swift-version 5 -o /tmp/petsheet tools/petsheet.swift Sources/LimitHUD/PixelPet.swift && /tmp/petsheet design/pet-designs-v4.png

let W: CGFloat = 1500, H: CGFloat = 1180, S: CGFloat = 2
func hx(_ h: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((h >> 16) & 0xFF)/255, green: CGFloat((h >> 8) & 0xFF)/255,
            blue: CGFloat(h & 0xFF)/255, alpha: a)
}
let ink = hx(0xF4F4F5), muted = hx(0xF4F4F5, 0.55), muted2 = hx(0xF4F4F5, 0.34)

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W*S), pixelsHigh: Int(H*S),
                          bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                          colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let nsctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = nsctx
let ctx = nsctx.cgContext
ctx.scaleBy(x: S, y: S)
ctx.translateBy(x: 0, y: H); ctx.scaleBy(x: 1, y: -1)
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)

@discardableResult
func text(_ str: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat,
          _ color: NSColor, weight: NSFont.Weight = .regular, mono: Bool = false, kern: CGFloat = 0) -> CGFloat {
    let f = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
                 : NSFont.systemFont(ofSize: size, weight: weight)
    var a: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: color]
    if kern != 0 { a[.kern] = kern }
    (str as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: a)
    return (str as NSString).size(withAttributes: a).width
}

func blit(_ img: NSImage, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) {
    img.draw(in: NSRect(x: x, y: y, width: w, height: h), from: .zero,
             operation: .sourceOver, fraction: 1, respectFlipped: true,
             hints: [.interpolation: NSImageInterpolation.none.rawValue])
}

ctx.setFillColor(hx(0x0E0E10).cgColor)
ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
text("LIMITHUD · PET SHEET (PRODUCTION RENDERER) — MORANDI", 90, 48, 17, muted, weight: .bold, mono: true, kern: 3)
text("Per-character state behavior · sage / dusty mustard / dusty rose", 90, 76, 14, muted2, mono: true)

let states = ["healthy", "caution", "danger", "dead", "party"]
let stateLabels = ["HEALTHY ≥50%", "CAUTION <50%", "DANGER <20%", "DEAD", "PARTY · refill"]
let designs: [(name: String, cn: String, style: String)] = [
    ("MOCHI", "团子", "mochi"),
    ("NEKO", "圆猫", "neko"),
    ("BOO", "小幽灵", "boo"),
    ("INU", "小狗", "inu"),
]

let gridX: CGFloat = 230, colW: CGFloat = 248, rowH: CGFloat = 224, gridY: CGFloat = 124
for (i, label) in stateLabels.enumerated() {
    text(label, gridX + CGFloat(i)*colW + 24, 106, 13, muted2, weight: .bold, mono: true, kern: 1)
}
MainActor.assumeIsolated {
    for (rI, d) in designs.enumerated() {
        let y = gridY + CGFloat(rI)*rowH
        text(d.name, 80, y + 78, 16, ink, weight: .bold, mono: true, kern: 1)
        text(d.cn, 80, y + 104, 14, muted2)
        ctx.setFillColor(hx(0xF4F4F5, 0.05).cgColor)
        ctx.fill(CGRect(x: 70, y: y + rowH - 18, width: W - 160, height: 1))
        for (cI, st) in states.enumerated() {
            let img = PixelPet.sprite(style: d.style, state: st, grid: 36)
            blit(img, x: gridX + CGFloat(cI)*colW + 22, y: y + 6, w: 168, h: 168)
        }
    }

    // menu bar size strip
    let simY = gridY + CGFloat(designs.count)*rowH + 10
    text("ACTUAL MENU BAR SIZE", 90, simY, 13, muted2, weight: .bold, mono: true, kern: 2)
    var sx: CGFloat = 90
    for d in designs {
        let barW: CGFloat = 300, barH: CGFloat = 32
        let bar = CGRect(x: sx, y: simY + 26, width: barW, height: barH)
        ctx.addPath(CGPath(roundedRect: bar, cornerWidth: 7, cornerHeight: 7, transform: nil))
        ctx.setFillColor(hx(0x1C1C1F).cgColor); ctx.fillPath()
        blit(PixelPet.sprite(style: d.style, state: "healthy", grid: 18), x: sx + 12, y: simY + 26 + 7, w: 18, h: 18)
        text("Claude 63%", sx + 38, simY + 26 + 8, 13, ink, weight: .medium, mono: true)
        blit(PixelPet.sprite(style: d.style, state: "danger", grid: 18), x: sx + 150, y: simY + 26 + 7, w: 18, h: 18)
        text("Codex 14%", sx + 176, simY + 26 + 8, 13, hx(0xC47A7A), weight: .medium, mono: true)
        sx += barW + 36
    }
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "design/pet-designs-v4.png"
try! FileManager.default.createDirectory(atPath: (out as NSString).deletingLastPathComponent,
                                         withIntermediateDirectories: true)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
