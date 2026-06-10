import AppKit

// Renders a polished product/hero image for LimitHUD.
// Usage: swift tools/heroimage.swift docs/hero.png

let W: CGFloat = 1600, H: CGFloat = 900, S: CGFloat = 2
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

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W*S), pixelsHigh: Int(H*S),
                          bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                          colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let nsctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = nsctx
let ctx = nsctx.cgContext
ctx.scaleBy(x: S, y: S)
ctx.translateBy(x: 0, y: H); ctx.scaleBy(x: 1, y: -1) // flip → top-left, y down
// Make NSString.draw render upright in this y-down space (shapes use ctx directly, unaffected).
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)

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

// ───── Background ─────
ctx.setFillColor(C(0.055, 0.055, 0.063).cgColor)
ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
if let g = CGGradient(colorsSpace: sRGB, colors: [C(0.10,0.10,0.11).cgColor, C(0.04,0.04,0.05).cgColor] as CFArray, locations: [0,1]) {
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: H), options: [])
}
// moss glow top-right
ctx.saveGState()
if let g = CGGradient(colorsSpace: sRGB, colors: [C(0.20,0.79,0.51,0.14).cgColor, C(0.20,0.79,0.51,0).cgColor] as CFArray, locations: [0,1]) {
    ctx.drawRadialGradient(g, startCenter: CGPoint(x: 1230, y: 250), startRadius: 0,
                           endCenter: CGPoint(x: 1230, y: 250), endRadius: 680, options: [])
}
ctx.restoreGState()
// faint grid dots
ctx.setFillColor(C(1,1,1,0.025).cgColor)
var gy: CGFloat = 40
while gy < H { var gx: CGFloat = 40; while gx < W { ctx.fillEllipse(in: CGRect(x: gx, y: gy, width: 2, height: 2)); gx += 46 }; gy += 46 }

// ───── Left column ─────
let lx: CGFloat = 120

// app icon
func drawIcon(_ x: CGFloat, _ y: CGFloat, _ side: CGFloat) {
    let rect = CGRect(x: x, y: y, width: side, height: side)
    let sq = roundedPath(rect, side*0.2237)
    ctx.saveGState(); ctx.addPath(sq); ctx.clip()
    if let g = CGGradient(colorsSpace: sRGB, colors: [C(0.105,0.105,0.115).cgColor, C(0.045,0.045,0.055).cgColor] as CFArray, locations: [0,1]) {
        ctx.drawLinearGradient(g, start: CGPoint(x: x, y: y), end: CGPoint(x: x, y: y+side), options: [])
    }
    ctx.restoreGState()
    ctx.addPath(sq); ctx.setStrokeColor(C(1,1,1,0.09).cgColor); ctx.setLineWidth(1.2); ctx.strokePath()
    // gauge
    let c = CGPoint(x: x+side/2, y: y+side/2), r = side*0.30, lw = side*0.09
    ctx.setLineCap(.round); ctx.setLineWidth(lw)
    func deg(_ d: CGFloat) -> CGFloat { d * .pi/180 }
    ctx.setStrokeColor(C(1,1,1,0.12).cgColor)
    ctx.addArc(center: c, radius: r, startAngle: deg(135), endAngle: deg(45), clockwise: false); ctx.strokePath()
    ctx.setStrokeColor(green.cgColor)
    ctx.addArc(center: c, radius: r, startAngle: deg(135), endAngle: deg(135+0.72*270), clockwise: false); ctx.strokePath()
    text("%", x+side*0.36, y+side*0.34, side*0.30, ink, weight: .bold, mono: true)
}
drawIcon(lx, 150, 92)

text("LimitHUD", lx, 270, 74, ink, weight: .bold, kern: -1)
text("Live Claude & Codex quota — right on your Mac.", lx, 372, 25, muted)

// feature lines
let feats = ["Always-on-top floating card", "Threshold & recovery alerts", "Works with Chrome, Brave, Edge, Arc…", "Local & open source — nothing leaves your Mac"]
var fy: CGFloat = 452
for f in feats {
    ctx.setFillColor(green.cgColor)
    ctx.addPath(roundedPath(CGRect(x: lx+2, y: fy+9, width: 9, height: 9), 2)); ctx.fillPath()
    text(f, lx+28, fy, 22, ink, weight: .medium)
    fy += 46
}

// url + badges row
text("github.com/zetagao/LimitHUD", lx, 770, 21, muted, mono: true)
// small pills
func pill(_ s: String, _ x: CGFloat, _ y: CGFloat, _ color: NSColor) -> CGFloat {
    let tw = textW(s, 13, weight: .bold, mono: true, kern: 1)
    let w = tw + 26, h: CGFloat = 28
    ctx.addPath(roundedPath(CGRect(x: x, y: y, width: w, height: h), h/2))
    ctx.setFillColor(color.withAlphaComponent(0.12).cgColor); ctx.fillPath()
    ctx.addPath(roundedPath(CGRect(x: x, y: y, width: w, height: h), h/2))
    ctx.setStrokeColor(color.withAlphaComponent(0.30).cgColor); ctx.setLineWidth(1); ctx.strokePath()
    text(s, x+13, y+7, 13, color, weight: .bold, mono: true, kern: 1)
    return w
}
var px = lx
px += pill("FREE", px, 700, green) + 10
px += pill("MIT", px, 700, C(0.69,0.59,0.99)) + 10
px += pill("macOS 13+", px, 700, muted) + 10

// ───── Right: card mockup ─────
let CW: CGFloat = 384
let cx = W - CW - 150
let pad: CGFloat = 22
struct Row { let label: String; let pct: Int; let cd: String; let color: NSColor }
struct Sec { let name: String; let rows: [Row] }
let secs = [
    Sec(name: "CLAUDE", rows: [Row(label:"5-Hour", pct:62, cd:"2h 18m", color:green), Row(label:"7-Day", pct:88, cd:"4d 3h", color:green)]),
    Sec(name: "CODEX",  rows: [Row(label:"5-Hour", pct:14, cd:"41m", color:red), Row(label:"7-Day", pct:71, cd:"1d 18h", color:green)]),
]

// measure height
var ch = pad + 26 // header
for s in secs { ch += 30 + CGFloat(s.rows.count)*48 + 10 }
ch += 14 + 30 + pad // divider + footer
let cy = (H - ch)/2

// green glow behind card
ctx.saveGState()
if let g = CGGradient(colorsSpace: sRGB, colors: [C(0.20,0.79,0.51,0.13).cgColor, C(0.20,0.79,0.51,0).cgColor] as CFArray, locations: [0,1]) {
    ctx.drawRadialGradient(g, startCenter: CGPoint(x: cx+CW/2, y: cy+ch/2), startRadius: 0,
                           endCenter: CGPoint(x: cx+CW/2, y: cy+ch/2), endRadius: 420, options: [])
}
ctx.restoreGState()

// card shadow + surface
let cardRect = CGRect(x: cx, y: cy, width: CW, height: ch)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 24), blur: 60, color: C(0,0,0,0.55).cgColor)
ctx.addPath(roundedPath(cardRect, 26)); ctx.setFillColor(C(0.086,0.086,0.094).cgColor); ctx.fillPath()
ctx.restoreGState()
ctx.addPath(roundedPath(cardRect, 26)); ctx.setStrokeColor(C(1,1,1,0.12).cgColor); ctx.setLineWidth(1); ctx.strokePath()
// top highlight
ctx.saveGState(); ctx.addPath(roundedPath(cardRect, 26)); ctx.clip()
if let g = CGGradient(colorsSpace: sRGB, colors: [C(1,1,1,0.06).cgColor, C(1,1,1,0).cgColor] as CFArray, locations: [0,1]) {
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: cy), end: CGPoint(x: 0, y: cy+90), options: [])
}
ctx.restoreGState()

var y = cy + pad
let tx = cx + pad
// header
ctx.setFillColor(green.cgColor); ctx.fillEllipse(in: CGRect(x: tx, y: y+6, width: 9, height: 9))
text("AI QUOTA", tx+18, y, 15, muted, weight: .bold, kern: 2)
for (i, gx) in [CW-pad-66, CW-pad-44, CW-pad-22].enumerated() {
    let _ = i
    ctx.setStrokeColor(muted2.cgColor); ctx.setLineWidth(1.6)
    ctx.strokeEllipse(in: CGRect(x: cx+gx, y: y-1, width: 15, height: 15))
}
y += 40

let barW = CW - pad*2
for s in secs {
    text(s.name, tx, y, 14, muted2, weight: .bold, kern: 2.4)
    y += 30
    for r in s.rows {
        text(r.label, tx, y, 18, ink, weight: .medium)
        // right group
        let pctStr = "\(r.pct)%"
        let leftStr = " left"
        let cdStr = "  \(r.cd)"
        let wCd = textW(cdStr, 15, mono: true)
        let wLeft = textW(leftStr, 13, weight: .medium, mono: true)
        let wPct = textW(pctStr, 17, weight: .semibold, mono: true)
        var rx = cx + CW - pad - wCd
        text(cdStr, rx, y+2, 15, muted2, mono: true)
        rx -= wLeft
        text(leftStr, rx, y+4, 13, muted2, weight: .medium, mono: true)
        rx -= wPct
        text(pctStr, rx, y, 17, r.color, weight: .semibold, mono: true)
        y += 28
        // bar
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
// divider + footer
ctx.setFillColor(C(1,1,1,0.08).cgColor); ctx.fill(CGRect(x: tx, y: y, width: barW, height: 1))
y += 14
text("SYNCED 15:49", tx, y, 13, muted2, weight: .bold, mono: true, kern: 0.5)
let kb = "⌘⇧L"
let kbw = textW(kb, 13, weight: .medium, mono: true)
ctx.addPath(roundedPath(CGRect(x: cx+CW-pad-kbw-12, y: y-3, width: kbw+12, height: 22), 5))
ctx.setStrokeColor(C(1,1,1,0.12).cgColor); ctx.setLineWidth(1); ctx.strokePath()
text(kb, cx+CW-pad-kbw-6, y+1, 13, muted2, weight: .medium, mono: true)

// ───── write ─────
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "docs/hero.png"
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
