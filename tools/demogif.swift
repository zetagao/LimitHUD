import AppKit
import ImageIO

// Renders the animated product demo GIF for LimitHUD (no app launch needed).
// Usage: swift tools/demogif.swift docs/demo.gif
// Also writes /tmp/limithud-demo-check-{1,2,3}.png key frames for review.

let W: CGFloat = 760, H: CGFloat = 500, S: CGFloat = 2
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
func C(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}
let ink = C(0.957, 0.957, 0.961)
let muted = C(0.957, 0.957, 0.961, 0.6)
let muted2 = C(0.957, 0.957, 0.961, 0.36)
let green = C(0.204, 0.788, 0.510)
let amber = C(0.961, 0.784, 0.259)
let red   = C(0.910, 0.282, 0.333)

var ctx: CGContext!

func roundedPath(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}
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
func textW(_ str: String, _ size: CGFloat, weight: NSFont.Weight = .regular, mono: Bool = false, kern: CGFloat = 0) -> CGFloat {
    let f = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
                 : NSFont.systemFont(ofSize: size, weight: weight)
    var a: [NSAttributedString.Key: Any] = [.font: f]
    if kern != 0 { a[.kern] = kern }
    return (str as NSString).size(withAttributes: a).width
}

// ───── scene model ─────
struct FrameSpec {
    var menuPct: Int
    var menuColor: NSColor
    var clicked = false
    var card: CGFloat = 0      // 0..1 fade/slide-in
    var glow: CGFloat = 0      // forecast highlight pulse
    var notif: CGFloat = 0     // notification slide-in
    var caption: String
    var endCard = false
    var delay: Double
}

// ───── shared pieces ─────
func drawBackground() {
    ctx.setFillColor(C(0.055, 0.055, 0.063).cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
    if let g = CGGradient(colorsSpace: sRGB, colors: [C(0.10,0.10,0.11).cgColor, C(0.04,0.04,0.05).cgColor] as CFArray, locations: [0,1]) {
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: H), options: [])
    }
    ctx.setFillColor(C(1,1,1,0.025).cgColor)
    var gy: CGFloat = 40
    while gy < H { var gx: CGFloat = 40; while gx < W { ctx.fillEllipse(in: CGRect(x: gx, y: gy, width: 2, height: 2)); gx += 46 }; gy += 46 }
}

func drawIcon(_ x: CGFloat, _ y: CGFloat, _ side: CGFloat) {
    let rect = CGRect(x: x, y: y, width: side, height: side)
    let sq = roundedPath(rect, side*0.2237)
    ctx.saveGState(); ctx.addPath(sq); ctx.clip()
    if let g = CGGradient(colorsSpace: sRGB, colors: [C(0.105,0.105,0.115).cgColor, C(0.045,0.045,0.055).cgColor] as CFArray, locations: [0,1]) {
        ctx.drawLinearGradient(g, start: CGPoint(x: x, y: y), end: CGPoint(x: x, y: y+side), options: [])
    }
    ctx.restoreGState()
    ctx.addPath(sq); ctx.setStrokeColor(C(1,1,1,0.09).cgColor); ctx.setLineWidth(1.2); ctx.strokePath()
    let c = CGPoint(x: x+side/2, y: y+side/2), r = side*0.30, lw = side*0.09
    ctx.setLineCap(.round); ctx.setLineWidth(lw)
    func deg(_ d: CGFloat) -> CGFloat { d * .pi/180 }
    ctx.setStrokeColor(C(1,1,1,0.12).cgColor)
    ctx.addArc(center: c, radius: r, startAngle: deg(135), endAngle: deg(45), clockwise: false); ctx.strokePath()
    ctx.setStrokeColor(green.cgColor)
    ctx.addArc(center: c, radius: r, startAngle: deg(135), endAngle: deg(135+0.72*270), clockwise: false); ctx.strokePath()
    text("%", x+side*0.36, y+side*0.34, side*0.30, ink, weight: .bold, mono: true)
}

// menu bar; returns center x of the status item (card anchors under it)
let mbH: CGFloat = 32
func drawMenuBar(_ spec: FrameSpec) -> CGFloat {
    ctx.setFillColor(C(0.10, 0.10, 0.112).cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: W, height: mbH))
    ctx.setFillColor(C(1,1,1,0.07).cgColor)
    ctx.fill(CGRect(x: 0, y: mbH, width: W, height: 1))
    // left: apple + app menus
    var x: CGFloat = 18
    x += text("\u{F8FF}", x, 7, 15, ink) + 18
    x += text("Finder", x, 8, 14, ink, weight: .semibold) + 18
    for m in ["File", "Edit", "View", "Go"] { x += text(m, x, 8, 14, muted) + 18 }
    // right: clock
    let clock = "Wed 10:42"
    let cw = textW(clock, 13, weight: .medium)
    text(clock, W-18-cw, 9, 13, ink, weight: .medium)
    // battery glyph
    let bx = W-18-cw-46
    ctx.setStrokeColor(muted.cgColor); ctx.setLineWidth(1.2)
    ctx.addPath(roundedPath(CGRect(x: bx, y: 11, width: 22, height: 10), 3)); ctx.strokePath()
    ctx.setFillColor(muted.cgColor)
    ctx.fill(CGRect(x: bx+2, y: 13, width: 13, height: 6))
    ctx.fill(CGRect(x: bx+23.5, y: 14, width: 2, height: 4))
    // the LimitHUD status item
    let label = "\(spec.menuPct)%"
    let lw = textW(label, 13, weight: .semibold, mono: true)
    let itemW = lw + 20
    let ix = bx - 16 - itemW
    if spec.clicked || spec.card > 0 {
        ctx.addPath(roundedPath(CGRect(x: ix, y: 3, width: itemW, height: mbH-6), 5))
        ctx.setFillColor(C(1,1,1,0.16).cgColor); ctx.fillPath()
    }
    text(label, ix+10, 8, 13, spec.menuColor, weight: .semibold, mono: true)
    return ix + itemW/2
}

// ───── the card (drawn in heroimage coordinates, scaled by k) ─────
struct Row { let label: String; let pct: Int; let cd: String; let color: NSColor }
struct Sec { let name: String; let rows: [Row] }
let secs = [
    Sec(name: "CLAUDE", rows: [Row(label:"5-Hour", pct:19, cd:"41m", color:red), Row(label:"7-Day", pct:71, cd:"4d 3h", color:green)]),
    Sec(name: "CODEX",  rows: [Row(label:"5-Hour", pct:64, cd:"2h 18m", color:green), Row(label:"7-Day", pct:88, cd:"5d 11h", color:green)]),
]
let CW: CGFloat = 384, heroH: CGFloat = 150, pad: CGFloat = 22
let cardH: CGFloat = {
    var ch = pad + 40 + heroH + 18
    for s in secs { ch += 30 + CGFloat(s.rows.count)*48 + 10 }
    return ch + 14 + 30 + pad
}()
let k: CGFloat = 0.62

// returns the forecast-line rect in card-local coords (for the glow ring)
@discardableResult
func drawCard(glow: CGFloat) -> CGRect {
    let cardRect = CGRect(x: 0, y: 0, width: CW, height: cardH)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 18), blur: 44, color: C(0,0,0,0.55).cgColor)
    ctx.addPath(roundedPath(cardRect, 26)); ctx.setFillColor(C(0.086,0.086,0.094).cgColor); ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(roundedPath(cardRect, 26)); ctx.setStrokeColor(C(1,1,1,0.12).cgColor); ctx.setLineWidth(1); ctx.strokePath()
    ctx.saveGState(); ctx.addPath(roundedPath(cardRect, 26)); ctx.clip()
    if let g = CGGradient(colorsSpace: sRGB, colors: [C(1,1,1,0.06).cgColor, C(1,1,1,0).cgColor] as CFArray, locations: [0,1]) {
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: 90), options: [])
    }
    ctx.restoreGState()

    var y = pad
    let tx = pad
    let barW = CW - pad*2
    ctx.setFillColor(red.cgColor); ctx.fillEllipse(in: CGRect(x: tx, y: y+6, width: 9, height: 9))
    text("AI QUOTA", tx+18, y, 15, muted, weight: .bold, kern: 2)
    for (i, gx) in [CW-pad-88, CW-pad-66, CW-pad-44, CW-pad-22].enumerated() {
        let isPin = (i == 2)
        ctx.setStrokeColor((isPin ? green : muted2).cgColor); ctx.setLineWidth(1.6)
        ctx.strokeEllipse(in: CGRect(x: gx, y: y-1, width: 15, height: 15))
        if isPin { ctx.setFillColor(green.withAlphaComponent(0.5).cgColor); ctx.fillEllipse(in: CGRect(x: gx+5, y: y+3, width: 5, height: 5)) }
    }
    y += 40

    // bottleneck hero — CLAUDE · 5-HOUR, red
    let hero = secs[0].rows[0]
    let heroRect = CGRect(x: tx, y: y, width: barW, height: heroH)
    ctx.addPath(roundedPath(heroRect, 16)); ctx.setFillColor(hero.color.withAlphaComponent(0.08).cgColor); ctx.fillPath()
    ctx.addPath(roundedPath(heroRect, 16)); ctx.setStrokeColor(hero.color.withAlphaComponent(0.22).cgColor); ctx.setLineWidth(1); ctx.strokePath()
    let hp: CGFloat = 18
    var hy = y + 16
    text("CLAUDE · 5-HOUR", tx+hp, hy, 13, muted2, weight: .bold, kern: 1.6)
    text(hero.cd, CW-pad-hp-textW(hero.cd, 13, mono: true), hy, 13, muted2, mono: true)
    hy += 24
    let bigW = text("\(hero.pct)", tx+hp, hy, 46, hero.color, weight: .bold, mono: true)
    text("% left", tx+hp+bigW+8, hy+24, 16, muted, weight: .medium, mono: true)
    // sparkline
    let spX = CW-pad-hp-96, spY = hy+6, spW: CGFloat = 96, spH: CGFloat = 40
    let pts: [CGFloat] = [0.82, 0.74, 0.7, 0.55, 0.43, 0.3, 0.22, 0.14]
    func spPoint(_ i: Int) -> CGPoint {
        CGPoint(x: spX + spW*CGFloat(i)/CGFloat(pts.count-1), y: spY + spH*(1 - pts[i]))
    }
    ctx.saveGState()
    let area = CGMutablePath()
    area.move(to: CGPoint(x: spX, y: spY+spH))
    for i in pts.indices { area.addLine(to: spPoint(i)) }
    area.addLine(to: CGPoint(x: spX+spW, y: spY+spH)); area.closeSubpath()
    ctx.addPath(area); ctx.clip()
    if let g = CGGradient(colorsSpace: sRGB, colors: [hero.color.withAlphaComponent(0.28).cgColor, hero.color.withAlphaComponent(0).cgColor] as CFArray, locations: [0,1]) {
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: spY), end: CGPoint(x: 0, y: spY+spH), options: [])
    }
    ctx.restoreGState()
    ctx.setStrokeColor(hero.color.cgColor); ctx.setLineWidth(2); ctx.setLineJoin(.round); ctx.setLineCap(.round)
    ctx.move(to: spPoint(0)); for i in pts.indices.dropFirst() { ctx.addLine(to: spPoint(i)) }; ctx.strokePath()
    hy = y + heroH - 50
    ctx.addPath(roundedPath(CGRect(x: tx+hp, y: hy, width: barW-hp*2, height: 9), 4.5)); ctx.setFillColor(C(1,1,1,0.08).cgColor); ctx.fillPath()
    ctx.saveGState(); ctx.setShadow(offset: .zero, blur: 8, color: hero.color.withAlphaComponent(0.5).cgColor)
    ctx.addPath(roundedPath(CGRect(x: tx+hp, y: hy, width: max(8,(barW-hp*2)*CGFloat(hero.pct)/100), height: 9), 4.5)); ctx.setFillColor(hero.color.cgColor); ctx.fillPath()
    ctx.restoreGState()
    hy += 22
    text("🔥", tx+hp, hy-2, 13, hero.color)
    text("empty in ~22m at this rate", tx+hp+22, hy, 14, hero.color.withAlphaComponent(0.92), weight: .medium, mono: true)
    let fcRect = CGRect(x: tx+hp-8, y: hy-6, width: textW("empty in ~22m at this rate", 14, weight: .medium, mono: true)+22+16, height: 28)
    if glow > 0 {
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 12, color: hero.color.withAlphaComponent(0.7*glow).cgColor)
        ctx.addPath(roundedPath(fcRect, 8))
        ctx.setStrokeColor(hero.color.withAlphaComponent(glow).cgColor); ctx.setLineWidth(1.6); ctx.strokePath()
        ctx.restoreGState()
    }
    y += heroH + 18

    for s in secs {
        text(s.name, tx, y, 14, muted2, weight: .bold, kern: 2.4)
        y += 30
        for r in s.rows {
            text(r.label, tx, y, 18, ink, weight: .medium)
            let pctStr = "\(r.pct)%", leftStr = " left", cdStr = "  \(r.cd)"
            let wCd = textW(cdStr, 15, mono: true)
            let wLeft = textW(leftStr, 13, weight: .medium, mono: true)
            let wPct = textW(pctStr, 17, weight: .semibold, mono: true)
            var rx = CW - pad - wCd
            text(cdStr, rx, y+2, 15, muted2, mono: true)
            rx -= wLeft
            text(leftStr, rx, y+4, 13, muted2, weight: .medium, mono: true)
            rx -= wPct
            text(pctStr, rx, y, 17, r.color, weight: .semibold, mono: true)
            y += 28
            ctx.addPath(roundedPath(CGRect(x: tx, y: y, width: barW, height: 7), 3.5)); ctx.setFillColor(C(1,1,1,0.08).cgColor); ctx.fillPath()
            let fillW = max(6, barW * CGFloat(r.pct)/100)
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: 8, color: r.color.withAlphaComponent(0.5).cgColor)
            ctx.addPath(roundedPath(CGRect(x: tx, y: y, width: fillW, height: 7), 3.5)); ctx.setFillColor(r.color.cgColor); ctx.fillPath()
            ctx.restoreGState()
            y += 20
        }
        y += 10
    }
    ctx.setFillColor(C(1,1,1,0.08).cgColor); ctx.fill(CGRect(x: tx, y: y, width: barW, height: 1))
    y += 14
    text("SYNCED 10:42", tx, y, 13, muted2, weight: .bold, mono: true, kern: 0.5)
    let kb = "⌘⇧L"
    let kbw = textW(kb, 13, weight: .medium, mono: true)
    ctx.addPath(roundedPath(CGRect(x: CW-pad-kbw-12, y: y-3, width: kbw+12, height: 22), 5))
    ctx.setStrokeColor(C(1,1,1,0.12).cgColor); ctx.setLineWidth(1); ctx.strokePath()
    text(kb, CW-pad-kbw-6, y+1, 13, muted2, weight: .medium, mono: true)
    return fcRect
}

func drawNotification(_ n: CGFloat) {
    let nw: CGFloat = 296, nh: CGFloat = 64
    let nx = W - 16 - nw + (1-n)*60
    let ny = mbH + 12
    ctx.saveGState()
    ctx.setAlpha(n)
    ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 28, color: C(0,0,0,0.5).cgColor)
    ctx.addPath(roundedPath(CGRect(x: nx, y: ny, width: nw, height: nh), 14))
    ctx.setFillColor(C(0.16,0.16,0.175).cgColor); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState(); ctx.setAlpha(n)
    ctx.addPath(roundedPath(CGRect(x: nx, y: ny, width: nw, height: nh), 14))
    ctx.setStrokeColor(C(1,1,1,0.12).cgColor); ctx.setLineWidth(1); ctx.strokePath()
    drawIcon(nx+12, ny+13, 38)
    text("LimitHUD", nx+62, ny+12, 13, ink, weight: .semibold)
    text("Claude 5-Hour running low", nx+62, ny+30, 12, muted)
    text("now", nx+nw-12-textW("now", 11), ny+13, 11, muted2)
    ctx.restoreGState()
}

func drawCaption(_ s: String) {
    guard !s.isEmpty else { return }
    let size: CGFloat = 21
    let w = textW(s, size, weight: .semibold)
    let x = (W - w - 26)/2
    let y = H - 58
    ctx.setFillColor(green.cgColor)
    ctx.addPath(roundedPath(CGRect(x: x, y: y+8, width: 9, height: 9), 2)); ctx.fillPath()
    text(s, x+26, y, size, ink, weight: .semibold)
}

func drawEndCard() {
    drawBackground()
    ctx.saveGState()
    if let g = CGGradient(colorsSpace: sRGB, colors: [C(0.20,0.79,0.51,0.12).cgColor, C(0.20,0.79,0.51,0).cgColor] as CFArray, locations: [0,1]) {
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: W/2, y: 170), startRadius: 0,
                               endCenter: CGPoint(x: W/2, y: 170), endRadius: 360, options: [])
    }
    ctx.restoreGState()
    drawIcon(W/2-46, 92, 92)
    let nameW = textW("LimitHUD", 44, weight: .bold, kern: -1)
    text("LimitHUD", (W-nameW)/2, 208, 44, ink, weight: .bold, kern: -1)
    let tag = "Live Claude & Codex quota — right on your Mac."
    text(tag, (W-textW(tag, 18))/2, 272, 18, muted)
    // brew command pill
    let cmd = "brew install --no-quarantine zetagao/tap/limithud"
    let cw2 = textW(cmd, 15, mono: true)
    let pw = cw2 + 44, ph: CGFloat = 44
    let prX = (W-pw)/2, prY: CGFloat = 326
    ctx.addPath(roundedPath(CGRect(x: prX, y: prY, width: pw, height: ph), 10))
    ctx.setFillColor(C(1,1,1,0.05).cgColor); ctx.fillPath()
    ctx.addPath(roundedPath(CGRect(x: prX, y: prY, width: pw, height: ph), 10))
    ctx.setStrokeColor(C(1,1,1,0.14).cgColor); ctx.setLineWidth(1); ctx.strokePath()
    text("$", prX+16, prY+12, 15, green, weight: .bold, mono: true)
    text(cmd, prX+32, prY+12, 15, ink, mono: true)
    let url = "github.com/zetagao/LimitHUD  ·  free & open source (MIT)"
    text(url, (W-textW(url, 15, mono: true))/2, 404, 15, muted, mono: true)
}

// ───── frame rendering ─────
func render(_ spec: FrameSpec) -> (NSBitmapImageRep, CGImage) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W*S), pixelsHigh: Int(H*S),
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                              colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let nsctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = nsctx
    ctx = nsctx.cgContext
    ctx.scaleBy(x: S, y: S)
    ctx.translateBy(x: 0, y: H); ctx.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)

    if spec.endCard {
        drawEndCard()
    } else {
        drawBackground()
        let itemCenter = drawMenuBar(spec)
        if spec.card > 0 {
            let cw = CW*k
            let cx = min(itemCenter - cw/2, W - cw - 14)
            let cy = mbH + 10 + (1 - spec.card) * 10
            ctx.saveGState()
            ctx.setAlpha(spec.card)
            ctx.translateBy(x: cx, y: cy)
            ctx.scaleBy(x: k, y: k)
            drawCard(glow: spec.glow)
            ctx.restoreGState()
        }
        if spec.notif > 0 { drawNotification(spec.notif) }
        drawCaption(spec.caption)
    }
    return (rep, rep.cgImage!)
}

// ───── storyboard ─────
let cap1 = "Your tightest quota — right in the menu bar"
let cap2 = "Quiet when healthy · amber under 50%"
let cap3 = "…red under 20%"
let cap4 = "Click to peek — your bottleneck, front and center"
let cap5 = "Burn-rate forecast: know before you run dry"
let cap6 = "Alerts below your threshold — and when quota is back"

var frames: [FrameSpec] = []
frames.append(FrameSpec(menuPct: 62, menuColor: ink, caption: cap1, delay: 2.0))
frames.append(FrameSpec(menuPct: 57, menuColor: ink, caption: cap1, delay: 0.28))
frames.append(FrameSpec(menuPct: 53, menuColor: ink, caption: cap1, delay: 0.28))
frames.append(FrameSpec(menuPct: 48, menuColor: amber, caption: cap2, delay: 1.6))
frames.append(FrameSpec(menuPct: 41, menuColor: amber, caption: cap2, delay: 0.24))
frames.append(FrameSpec(menuPct: 33, menuColor: amber, caption: cap2, delay: 0.24))
frames.append(FrameSpec(menuPct: 26, menuColor: amber, caption: cap2, delay: 0.24))
frames.append(FrameSpec(menuPct: 19, menuColor: red, caption: cap3, delay: 1.8))
frames.append(FrameSpec(menuPct: 19, menuColor: red, clicked: true, caption: cap4, delay: 0.35))
frames.append(FrameSpec(menuPct: 19, menuColor: red, card: 0.45, caption: cap4, delay: 0.07))
frames.append(FrameSpec(menuPct: 19, menuColor: red, card: 0.8, caption: cap4, delay: 0.07))
frames.append(FrameSpec(menuPct: 19, menuColor: red, card: 1, caption: cap4, delay: 2.6))
frames.append(FrameSpec(menuPct: 19, menuColor: red, card: 1, glow: 0.95, caption: cap5, delay: 0.4))
frames.append(FrameSpec(menuPct: 19, menuColor: red, card: 1, glow: 0.25, caption: cap5, delay: 0.3))
frames.append(FrameSpec(menuPct: 19, menuColor: red, card: 1, glow: 0.95, caption: cap5, delay: 0.4))
frames.append(FrameSpec(menuPct: 19, menuColor: red, card: 1, glow: 0.3, caption: cap5, delay: 1.2))
frames.append(FrameSpec(menuPct: 19, menuColor: red, card: 1, notif: 0.5, caption: cap6, delay: 0.08))
frames.append(FrameSpec(menuPct: 19, menuColor: red, card: 1, notif: 1, caption: cap6, delay: 2.4))
frames.append(FrameSpec(menuPct: 19, menuColor: red, caption: "", endCard: true, delay: 3.6))

// ───── encode ─────
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "docs/demo.gif"
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL,
                                           "com.compuserve.gif" as CFString, frames.count, nil)!
CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary as String:
                                       [kCGImagePropertyGIFLoopCount as String: 0]] as CFDictionary)
let checks = [0, 11, 17, frames.count-1]  // key frames written to /tmp for review
for (i, spec) in frames.enumerated() {
    let (rep, img) = render(spec)
    CGImageDestinationAddImage(dest, img, [kCGImagePropertyGIFDictionary as String:
        [kCGImagePropertyGIFUnclampedDelayTime as String: spec.delay,
         kCGImagePropertyGIFDelayTime as String: spec.delay]] as CFDictionary)
    if let n = checks.firstIndex(of: i) {
        try? rep.representation(using: .png, properties: [:])?
            .write(to: URL(fileURLWithPath: "/tmp/limithud-demo-check-\(n+1).png"))
    }
}
guard CGImageDestinationFinalize(dest) else { fatalError("gif finalize failed") }
print("wrote \(out) (\(frames.count) frames)")
