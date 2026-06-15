import AppKit
import SwiftUI

/// Procedurally-drawn pet (no image assets), rendered onto a small pixel grid
/// with AA off for a fine-mosaic look. Each character has fixed natural colors
/// (mochi=sakura, cat=calico, dog=white Westie, ghost=translucent); the quota
/// state shows in the face, not the body color.
@MainActor
enum PixelPet {
    /// How long the party state sticks around after a refill.
    static let celebrationWindow: TimeInterval = 90

    /// Map quota → pet state name.
    static func state(remaining: Double?, lastRefill: Date?, now: Date = Date()) -> String {
        if let lr = lastRefill, now.timeIntervalSince(lr) < celebrationWindow { return "party" }
        guard let r = remaining else { return "sleep" }
        switch r {
        case 0.5...:      return "healthy"
        case 0.2..<0.5:   return "caution"
        case 0.05..<0.2:  return "danger"
        default:          return "dead"
        }
    }

    private static var cache: [String: NSImage] = [:]

    /// One full idle-animation loop, in frames (~20 fps → ~3.5s).
    static let animationFrames = 70

    static func sprite(style: String, state: String, grid: Int, frame: Int = 0) -> NSImage {
        let f = ((frame % animationFrames) + animationFrames) % animationFrames
        let key = "\(style)/\(state)/\(grid)/\(f)"
        if let img = cache[key] { return img }
        let img = render(style: style, state: state, grid: grid, frame: f)
        cache[key] = img
        return img
    }

    // MARK: palette helpers

    private static func rgb(_ h: UInt32, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((h >> 16) & 0xFF)/255, green: CGFloat((h >> 8) & 0xFF)/255,
                blue: CGFloat(h & 0xFF)/255, alpha: a)
    }
    private static func lighten(_ c: NSColor, _ f: CGFloat) -> NSColor {
        let c = c.usingColorSpace(.sRGB)!
        return NSColor(srgbRed: c.redComponent + (1 - c.redComponent)*f,
                       green: c.greenComponent + (1 - c.greenComponent)*f,
                       blue: c.blueComponent + (1 - c.blueComponent)*f, alpha: c.alphaComponent)
    }
    private static func darken(_ c: NSColor, _ f: CGFloat) -> NSColor {
        let c = c.usingColorSpace(.sRGB)!
        return NSColor(srgbRed: c.redComponent*(1-f), green: c.greenComponent*(1-f),
                       blue: c.blueComponent*(1-f), alpha: c.alphaComponent)
    }

    private static let ink = rgb(0x2C2A2E)
    private static let pink = rgb(0xE6A8B2)
    private static let blush = rgb(0xDB9C9C, 0.6)
    private static let sweatC = rgb(0x7FB5D6, 0.95)

    // MARK: renderer

    private static func render(style: String, state: String, grid N: Int, frame: Int) -> NSImage {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: N, pixelsHigh: N,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let saved = NSGraphicsContext.current
        let nc = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.current = nc
        let g = nc.cgContext
        g.setShouldAntialias(false)
        g.translateBy(x: 0, y: CGFloat(N)); g.scaleBy(x: 1, y: -1) // y-down
        draw(g, style: style, state: state, n: CGFloat(N), frame: frame)
        NSGraphicsContext.current = saved
        let img = NSImage(size: NSSize(width: N, height: N))
        img.addRepresentation(rep)
        return img
    }

    private static func draw(_ g: CGContext, style: String, state: String, n: CGFloat, frame: Int) {
        let isDead = state == "dead", isParty = state == "party"
        let cx = n/2, baseY = n * 0.9, r = n * 0.30

        // idle breathing / bob, anchored at the feet
        let loop = animationFrames
        let f = ((frame % loop) + loop) % loop
        let a = 2 * Double.pi * Double(f) / Double(loop)
        let blink = !isDead && !isParty && (f == loop - 3 || f == loop - 2)
        var sx: CGFloat = 1, sy: CGFloat = 1, dx: CGFloat = 0, dy: CGFloat = 0
        if !isDead {
            switch state {
            case "party":
                let hh = CGFloat(abs(sin(a)))
                dy = -0.13*r*hh; sy = 1 + 0.10*hh - 0.08*(1-hh); sx = 1 - 0.10*hh + 0.08*(1-hh)
            case "danger":
                let br = CGFloat(sin(a)); sy = 1 + 0.035*br; sx = 1 - 0.03*br
                dx = 0.02*r*CGFloat(sin(a*4)); dy = 0.025*r*CGFloat(cos(a))
            case "sleep":
                let br = CGFloat(sin(a)); sy = 1 + 0.08*br; sx = 1 - 0.06*br; dy = 0.03*r*CGFloat(cos(a))
            default:
                let br = CGFloat(sin(a)); sy = 1 + 0.05*br; sx = 1 - 0.04*br; dy = 0.05*r*CGFloat(cos(a))
            }
        }
        g.saveGState()
        g.translateBy(x: cx + dx, y: baseY + dy)
        g.scaleBy(x: sx, y: sy)
        g.translateBy(x: -cx, y: -baseY)

        switch style {
        case "neko": drawCat(g, n, state, blink)
        case "inu":  drawDog(g, n, state, blink)
        case "boo":  drawGhost(g, n, state, blink)
        default:     drawMochi(g, n, state, blink)
        }

        g.restoreGState()
    }

    // MARK: shared drawing helpers

    private static func furBlob(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat, _ bumps: Int, _ amp: CGFloat) -> CGMutablePath {
        let p = CGMutablePath()
        func pt(_ ang: CGFloat) -> CGPoint { CGPoint(x: cx + cos(ang)*rx, y: cy + sin(ang)*ry) }
        let step = 2*CGFloat.pi/CGFloat(bumps)
        p.move(to: pt(0))
        for i in 0..<bumps {
            let a0 = CGFloat(i)*step, mid = a0+step/2, a1 = a0+step
            p.addQuadCurve(to: pt(a1), control: CGPoint(x: cx+cos(mid)*(rx+amp), y: cy+sin(mid)*(ry+amp)))
        }
        p.closeSubpath(); return p
    }
    private static func cel(_ g: CGContext, _ path: CGPath, _ base: NSColor, _ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ outline: NSColor) {
        g.saveGState(); g.addPath(path); g.clip()
        g.setFillColor(base.cgColor); g.fill(CGRect(x: cx-3*r, y: cy-3*r, width: 6*r, height: 6*r))
        g.setFillColor(lighten(base, 0.20).cgColor); g.fill(CGRect(x: cx-3*r, y: cy-3*r, width: 6*r, height: 3*r - 0.55*r))
        g.restoreGState()
        g.addPath(path); g.setStrokeColor(outline.cgColor); g.setLineWidth(1); g.strokePath()
    }
    private static func padFoot(_ g: CGContext, _ pr: CGRect, _ white: NSColor, _ ol: NSColor, _ r: CGFloat) {
        g.setFillColor(white.cgColor); g.fillEllipse(in: pr)
        g.addPath(CGPath(ellipseIn: pr, transform: nil)); g.setStrokeColor(ol.cgColor); g.setLineWidth(1); g.strokePath()
        let fx = pr.midX, fy = pr.minY
        g.setFillColor(ink.cgColor)
        g.fillEllipse(in: CGRect(x: fx-0.11*r, y: fy+0.26*r, width: 0.22*r, height: 0.17*r))
        g.fillEllipse(in: CGRect(x: fx-0.14*r, y: fy+0.16*r, width: 0.08*r, height: 0.08*r))
        g.fillEllipse(in: CGRect(x: fx+0.06*r, y: fy+0.16*r, width: 0.08*r, height: 0.08*r))
    }
    private static func padHand(_ g: CGContext, _ x: CGFloat, _ y: CGFloat, _ aw: CGFloat, _ white: NSColor, _ ol: NSColor, _ r: CGFloat) {
        let arm = CGPath(roundedRect: CGRect(x: x, y: y, width: aw, height: 0.55*r), cornerWidth: aw/2, cornerHeight: aw/2, transform: nil)
        g.addPath(arm); g.setFillColor(white.cgColor); g.fillPath()
        g.addPath(arm); g.setStrokeColor(ol.cgColor); g.setLineWidth(1); g.strokePath()
        let hxc = x+aw*0.5
        g.setFillColor(ink.cgColor)
        g.fillEllipse(in: CGRect(x: hxc-0.065*r, y: y+0.39*r, width: 0.13*r, height: 0.1*r))
        g.fillEllipse(in: CGRect(x: hxc-0.11*r, y: y+0.28*r, width: 0.06*r, height: 0.06*r))
        g.fillEllipse(in: CGRect(x: hxc+0.05*r, y: y+0.28*r, width: 0.06*r, height: 0.06*r))
    }

    // MARK: face primitives (positioned by each character)

    private static func eyeClosed(_ g: CGContext, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ lw: CGFloat) {
        g.setStrokeColor(ink.cgColor); g.setLineWidth(lw); g.setLineCap(.round)
        g.move(to: CGPoint(x: x-w, y: y)); g.addLine(to: CGPoint(x: x+w, y: y)); g.strokePath()
    }
    private static func eyeGlossy(_ g: CGContext, _ x: CGFloat, _ y: CGFloat, _ er: CGFloat, iris: NSColor?) {
        if let iris {
            g.setFillColor(iris.cgColor); g.fillEllipse(in: CGRect(x: x-er, y: y-er*1.05, width: er*2, height: er*2.1))
            g.setFillColor(ink.cgColor); g.fillEllipse(in: CGRect(x: x-er*0.4, y: y-er*0.8, width: er*0.8, height: er*1.7))
            g.setFillColor(NSColor.white.cgColor); g.fillEllipse(in: CGRect(x: x+er*0.1, y: y-er*0.55, width: er*0.4, height: er*0.4))
        } else {
            g.setFillColor(ink.cgColor); g.fillEllipse(in: CGRect(x: x-er, y: y-er*1.1, width: er*2, height: er*2.2))
            g.setFillColor(NSColor.white.cgColor); g.fillEllipse(in: CGRect(x: x+er*0.05, y: y-er*0.8, width: er*0.55, height: er*0.55))
        }
    }
    private static func eyeHappy(_ g: CGContext, _ x: CGFloat, _ y: CGFloat, _ er: CGFloat, _ lw: CGFloat) {
        g.setStrokeColor(ink.cgColor); g.setLineWidth(lw); g.setLineCap(.round)
        g.move(to: CGPoint(x: x-er, y: y+er*0.4))
        g.addQuadCurve(to: CGPoint(x: x+er, y: y+er*0.4), control: CGPoint(x: x, y: y-er*1.1))
        g.strokePath()
    }
    private static func eyeX(_ g: CGContext, _ x: CGFloat, _ y: CGFloat, _ a: CGFloat, _ lw: CGFloat) {
        g.setStrokeColor(ink.cgColor); g.setLineWidth(lw); g.setLineCap(.round)
        g.move(to: CGPoint(x: x-a, y: y-a)); g.addLine(to: CGPoint(x: x+a, y: y+a)); g.strokePath()
        g.move(to: CGPoint(x: x+a, y: y-a)); g.addLine(to: CGPoint(x: x-a, y: y+a)); g.strokePath()
    }
    private static func eyeShock(_ g: CGContext, _ x: CGFloat, _ y: CGFloat, _ er: CGFloat) {
        let er2 = er*1.1
        g.setFillColor(NSColor.white.cgColor); g.fillEllipse(in: CGRect(x: x-er2, y: y-er2, width: er2*2, height: er2*2.1))
        g.setStrokeColor(ink.cgColor); g.setLineWidth(1); g.strokeEllipse(in: CGRect(x: x-er2, y: y-er2, width: er2*2, height: er2*2.1))
        g.setFillColor(ink.cgColor); g.fillEllipse(in: CGRect(x: x-er*0.32, y: y-er*0.3, width: er*0.64, height: er*0.7))
    }
    private static func mouthCurve(_ g: CGContext, _ cx: CGFloat, _ y: CGFloat, _ w: CGFloat, _ depth: CGFloat, _ lw: CGFloat) {
        g.setStrokeColor(ink.cgColor); g.setLineWidth(lw); g.setLineCap(.round)
        g.move(to: CGPoint(x: cx-w, y: y)); g.addQuadCurve(to: CGPoint(x: cx+w, y: y), control: CGPoint(x: cx, y: y+depth))
        g.strokePath()
    }
    private static func sweat(_ g: CGContext, _ sx: CGFloat, _ sy: CGFloat, _ r: CGFloat) {
        let drop = CGMutablePath()
        drop.move(to: CGPoint(x: sx, y: sy-0.18*r))
        drop.addQuadCurve(to: CGPoint(x: sx+0.11*r, y: sy+0.1*r), control: CGPoint(x: sx+0.16*r, y: sy-0.02*r))
        drop.addQuadCurve(to: CGPoint(x: sx-0.11*r, y: sy+0.1*r), control: CGPoint(x: sx, y: sy+0.26*r))
        drop.addQuadCurve(to: CGPoint(x: sx, y: sy-0.18*r), control: CGPoint(x: sx-0.16*r, y: sy-0.02*r))
        g.addPath(drop); g.setFillColor(sweatC.cgColor); g.fillPath()
    }

    /// Eyes for a character whose face sits at (cx, eyeY) with spacing eDX.
    /// `iris` is nil for plain dark eyes (dog/mochi/ghost), set for the cat.
    private static func eyes(_ g: CGContext, _ cx: CGFloat, _ eyeY: CGFloat, _ eDX: CGFloat, _ er: CGFloat,
                             _ r: CGFloat, state: String, blink: Bool, iris: NSColor?) {
        let lw = max(1, 0.05*r)
        if blink || state == "sleep" { eyeClosed(g, cx-eDX, eyeY, er, lw); eyeClosed(g, cx+eDX, eyeY, er, lw); return }
        switch state {
        case "dead":    eyeX(g, cx-eDX, eyeY, er*0.85, lw); eyeX(g, cx+eDX, eyeY, er*0.85, lw)
        case "party":   eyeHappy(g, cx-eDX, eyeY, er, lw); eyeHappy(g, cx+eDX, eyeY, er, lw)
        case "danger":  eyeShock(g, cx-eDX, eyeY, er); eyeShock(g, cx+eDX, eyeY, er)
        case "caution":
            eyeGlossy(g, cx-eDX, eyeY, er, iris: iris); eyeGlossy(g, cx+eDX, eyeY, er, iris: iris)
            // sleepy half-lids
            g.setFillColor(NSColor.clear.cgColor)
        default:        eyeGlossy(g, cx-eDX, eyeY, er, iris: iris); eyeGlossy(g, cx+eDX, eyeY, er, iris: iris)
        }
    }

    private static func partyHat(_ g: CGContext, _ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) {
        let top = CGPoint(x: cx+0.1*r, y: cy-1.75*r)
        let hat = CGMutablePath(); hat.move(to: top)
        hat.addLine(to: CGPoint(x: cx-0.34*r, y: cy-1.0*r)); hat.addLine(to: CGPoint(x: cx+0.42*r, y: cy-1.08*r)); hat.closeSubpath()
        g.addPath(hat); g.setFillColor(rgb(0xAE8FC9).cgColor); g.fillPath()
        g.setFillColor(rgb(0xDCC06E).cgColor); g.fillEllipse(in: CGRect(x: top.x-0.09*r, y: top.y-0.09*r, width: 0.18*r, height: 0.18*r))
    }
    private static func zMark(_ g: CGContext, _ zx: CGFloat, _ zy: CGFloat, _ r: CGFloat) {
        g.setStrokeColor(ink.withAlphaComponent(0.55).cgColor); g.setLineWidth(max(1, 0.04*r)); g.setLineCap(.round); g.setLineJoin(.round)
        let zs = 0.18*r
        g.move(to: CGPoint(x: zx, y: zy)); g.addLine(to: CGPoint(x: zx+zs, y: zy)); g.addLine(to: CGPoint(x: zx, y: zy+zs)); g.addLine(to: CGPoint(x: zx+zs, y: zy+zs)); g.strokePath()
    }

    // MARK: 🍡 mochi — sakura blob

    private static func drawMochi(_ g: CGContext, _ n: CGFloat, _ state: String, _ blink: Bool) {
        let cx = n/2, cy = n/2 + n*0.03, r = n*0.30
        let body = rgb(0xF2B8C6), ol = darken(body, 0.42), lw = max(1, 0.05*r)
        if state == "dead" { // melted puddle
            cel(g, CGPath(roundedRect: CGRect(x: cx-1.25*r, y: cy+0.4*r, width: 2.5*r, height: 0.72*r), cornerWidth: 0.36*r, cornerHeight: 0.36*r, transform: nil), body, cx, cy, r, ol)
            eyeX(g, cx-0.32*r, cy+0.66*r, 0.12*r, lw); eyeX(g, cx+0.32*r, cy+0.66*r, 0.12*r, lw)
            return
        }
        cel(g, CGPath(roundedRect: CGRect(x: cx-1.05*r, y: cy-0.92*r, width: 2.1*r, height: 1.95*r), cornerWidth: 0.88*r, cornerHeight: 0.88*r, transform: nil), body, cx, cy, r, ol)
        let eyeY = cy-0.18*r, eDX = 0.4*r, er = 0.17*r, my = cy+0.28*r
        eyes(g, cx, eyeY, eDX, er, r, state: state, blink: blink, iris: nil)
        switch state {
        case "party":
            let s = CGMutablePath(); s.move(to: CGPoint(x: cx-0.2*r, y: my-0.02*r)); s.addQuadCurve(to: CGPoint(x: cx+0.2*r, y: my-0.02*r), control: CGPoint(x: cx, y: my+0.34*r)); s.closeSubpath(); g.addPath(s); g.setFillColor(ink.cgColor); g.fillPath()
            partyHat(g, cx, cy, r)
        case "danger":
            g.setFillColor(ink.cgColor); g.fillEllipse(in: CGRect(x: cx-0.11*r, y: my, width: 0.22*r, height: 0.18*r))
            sweat(g, cx+0.8*r, cy-0.5*r, r); sweat(g, cx-0.86*r, cy-0.42*r, r)
        case "caution":
            mouthCurve(g, cx, my+0.06*r, 0.14*r, -0.02*r, lw); sweat(g, cx+0.8*r, cy-0.5*r, r)
        case "sleep":
            mouthCurve(g, cx, my, 0.1*r, 0.04*r, lw); zMark(g, cx+0.72*r, cy-0.86*r, r)
        default:
            mouthCurve(g, cx, my, 0.18*r, 0.22*r, lw)
        }
        if (state == "healthy" && !blink) || state == "party" {
            g.setFillColor(blush.cgColor)
            g.fillEllipse(in: CGRect(x: cx-eDX-0.28*r, y: cy+0.06*r, width: 0.28*r, height: 0.15*r))
            g.fillEllipse(in: CGRect(x: cx+eDX, y: cy+0.06*r, width: 0.28*r, height: 0.15*r))
        }
    }

    // MARK: 🐱 cat — calico longhair

    private static func drawCat(_ g: CGContext, _ n: CGFloat, _ state: String, _ blink: Bool) {
        let cx = n/2, cy = n/2 - n*0.02, r = n*0.24
        let white = rgb(0xF1EEE8), grey = rgb(0x615D67), ginger = rgb(0xD49B57), black = rgb(0x2C2A2E)
        let ol = darken(grey, 0.45)
        // plume tail
        let tail = furBlob(cx+1.45*r, cy+0.4*r, 0.5*r, 1.0*r, 9, 0.12*r)
        g.addPath(tail); g.setFillColor(grey.cgColor); g.fillPath(); g.addPath(tail); g.setStrokeColor(ol.cgColor); g.setLineWidth(1); g.strokePath()
        // body + markings
        let body = furBlob(cx, cy+0.85*r, 1.25*r, 1.15*r, 13, 0.1*r)
        g.saveGState(); g.addPath(body); g.clip()
        g.setFillColor(white.cgColor); g.fill(CGRect(x: cx-3*r, y: cy-3*r, width: 6*r, height: 8*r))
        g.setFillColor(grey.cgColor); g.fillEllipse(in: CGRect(x: cx-1.5*r, y: cy+0.1*r, width: 1.7*r, height: 1.4*r))
        g.setFillColor(ginger.cgColor); g.fillEllipse(in: CGRect(x: cx+0.35*r, y: cy+0.5*r, width: 1.0*r, height: 0.95*r))
        g.restoreGState()
        g.addPath(body); g.setStrokeColor(ol.cgColor); g.setLineWidth(1); g.strokePath()
        padFoot(g, CGRect(x: cx-0.54*r, y: cy+1.52*r, width: 0.46*r, height: 0.52*r), white, ol, r)
        padFoot(g, CGRect(x: cx+0.12*r, y: cy+1.52*r, width: 0.46*r, height: 0.52*r), white, ol, r)
        padHand(g, cx-0.52*r, cy+0.72*r, 0.36*r, white, ol, r)
        padHand(g, cx+0.16*r, cy+0.72*r, 0.36*r, white, ol, r)
        // ears
        func ear(_ sx: CGFloat, _ col: NSColor) {
            let e = CGMutablePath(); e.move(to: CGPoint(x: cx+sx*0.78*r, y: cy-0.5*r)); e.addLine(to: CGPoint(x: cx+sx*1.02*r, y: cy-1.5*r)); e.addLine(to: CGPoint(x: cx+sx*0.25*r, y: cy-0.78*r)); e.closeSubpath()
            g.addPath(e); g.setFillColor(col.cgColor); g.fillPath(); g.addPath(e); g.setStrokeColor(ol.cgColor); g.setLineWidth(1); g.strokePath()
            let inr = CGMutablePath(); inr.move(to: CGPoint(x: cx+sx*0.7*r, y: cy-0.6*r)); inr.addLine(to: CGPoint(x: cx+sx*0.88*r, y: cy-1.2*r)); inr.addLine(to: CGPoint(x: cx+sx*0.45*r, y: cy-0.78*r)); inr.closeSubpath()
            g.addPath(inr); g.setFillColor(pink.withAlphaComponent(0.85).cgColor); g.fillPath()
        }
        ear(-1, ginger); ear(1, black)
        // head + calico mask
        let head = furBlob(cx, cy-0.55*r, 1.0*r, 0.92*r, 12, 0.09*r)
        g.saveGState(); g.addPath(head); g.clip()
        g.setFillColor(white.cgColor); g.fill(CGRect(x: cx-3*r, y: cy-3*r, width: 6*r, height: 6*r))
        g.setFillColor(black.cgColor); g.fillEllipse(in: CGRect(x: cx+0.08*r, y: cy-1.5*r, width: 1.3*r, height: 1.45*r))
        g.setFillColor(ginger.cgColor); g.fillEllipse(in: CGRect(x: cx-1.0*r, y: cy-1.45*r, width: 0.95*r, height: 0.85*r))
        g.restoreGState()
        g.addPath(head); g.setStrokeColor(ol.cgColor); g.setLineWidth(1); g.strokePath()
        // face
        let eyeY = cy-0.6*r, eDX = 0.4*r, er = 0.16*r, lw = max(1, 0.05*r)
        eyes(g, cx, eyeY, eDX, er, r, state: state, blink: blink, iris: rgb(0x86B765))
        if state != "dead" { // pink nose + whiskers
            let nz = CGMutablePath(); nz.move(to: CGPoint(x: cx-0.1*r, y: cy-0.2*r)); nz.addLine(to: CGPoint(x: cx+0.1*r, y: cy-0.2*r)); nz.addLine(to: CGPoint(x: cx, y: cy-0.06*r)); nz.closeSubpath()
            g.addPath(nz); g.setFillColor(rgb(0xE08FA0).cgColor); g.fillPath()
            g.setStrokeColor(white.withAlphaComponent(0.7).cgColor); g.setLineWidth(1)
            for sx: CGFloat in [-1, 1] { g.move(to: CGPoint(x: cx+sx*0.25*r, y: cy-0.12*r)); g.addLine(to: CGPoint(x: cx+sx*1.0*r, y: cy-0.18*r)); g.strokePath() }
        }
        let my = cy+0.0*r
        switch state {
        case "healthy" where !blink:
            // ω mouth
            g.setStrokeColor(ink.cgColor); g.setLineWidth(lw); g.setLineCap(.round)
            g.move(to: CGPoint(x: cx-0.22*r, y: my)); g.addQuadCurve(to: CGPoint(x: cx, y: my), control: CGPoint(x: cx-0.11*r, y: my+0.2*r)); g.addQuadCurve(to: CGPoint(x: cx+0.22*r, y: my), control: CGPoint(x: cx+0.11*r, y: my+0.2*r)); g.strokePath()
        case "danger": g.setFillColor(ink.cgColor); g.fillEllipse(in: CGRect(x: cx-0.08*r, y: my, width: 0.16*r, height: 0.14*r))
        case "caution": angerMark(g, cx+0.72*r, cy-0.78*r, r)
        case "party":
            let s = CGMutablePath(); s.move(to: CGPoint(x: cx-0.2*r, y: my)); s.addQuadCurve(to: CGPoint(x: cx+0.2*r, y: my), control: CGPoint(x: cx, y: my+0.3*r)); s.closeSubpath(); g.addPath(s); g.setFillColor(ink.cgColor); g.fillPath()
        default: break
        }
    }
    private static func angerMark(_ g: CGContext, _ ax: CGFloat, _ ay: CGFloat, _ r: CGFloat) {
        g.setStrokeColor(rgb(0xC75555).cgColor); g.setLineWidth(max(1, 0.05*r)); g.setLineCap(.round); g.setLineJoin(.round)
        let u = 0.2*r, t = 0.08*r
        for ang in stride(from: CGFloat(0), to: 2*CGFloat.pi, by: .pi/2) {
            let tip = CGPoint(x: ax+cos(ang)*u*0.45, y: ay+sin(ang)*u*0.45), perp = ang + .pi/2
            let bx = ax+cos(ang)*u, by = ay+sin(ang)*u
            g.move(to: CGPoint(x: bx+cos(perp)*t, y: by+sin(perp)*t)); g.addLine(to: tip); g.addLine(to: CGPoint(x: bx-cos(perp)*t, y: by-sin(perp)*t)); g.strokePath()
        }
    }

    // MARK: 🐶 dog — white West Highland Terrier

    private static func drawDog(_ g: CGContext, _ n: CGFloat, _ state: String, _ blink: Bool) {
        let cx = n/2, cy = n/2 - n*0.02, r = n*0.25
        let white = rgb(0xF5F3EF), shade = rgb(0xD7D7DD), ol = rgb(0xB4B4BC), nose = rgb(0x24232A)
        let tail = furBlob(cx+1.0*r, cy+0.5*r, 0.32*r, 0.6*r, 7, 0.1*r)
        g.addPath(tail); g.setFillColor(white.cgColor); g.fillPath(); g.addPath(tail); g.setStrokeColor(ol.cgColor); g.setLineWidth(1); g.strokePath()
        let body = furBlob(cx, cy+0.9*r, 1.1*r, 1.05*r, 13, 0.09*r)
        cel(g, body, white, cx, cy, r, ol)
        g.saveGState(); g.addPath(body); g.clip(); g.setFillColor(shade.withAlphaComponent(0.5).cgColor); g.fillEllipse(in: CGRect(x: cx-1.1*r, y: cy+1.3*r, width: 2.2*r, height: 1.0*r)); g.restoreGState()
        padFoot(g, CGRect(x: cx-0.54*r, y: cy+1.55*r, width: 0.46*r, height: 0.52*r), white, ol, r)
        padFoot(g, CGRect(x: cx+0.12*r, y: cy+1.55*r, width: 0.46*r, height: 0.52*r), white, ol, r)
        padHand(g, cx-0.52*r, cy+0.78*r, 0.38*r, white, ol, r)
        padHand(g, cx+0.16*r, cy+0.78*r, 0.38*r, white, ol, r)
        // head + ears as one outline; SMOOTH round crown (no central bump)
        let head = CGMutablePath()
        head.move(to: CGPoint(x: cx-0.9*r, y: cy-0.28*r))
        head.addQuadCurve(to: CGPoint(x: cx-0.72*r, y: cy-0.95*r), control: CGPoint(x: cx-0.98*r, y: cy-0.62*r))
        head.addLine(to: CGPoint(x: cx-0.46*r, y: cy-1.58*r))                                  // left ear tip
        head.addQuadCurve(to: CGPoint(x: cx+0.46*r, y: cy-1.58*r), control: CGPoint(x: cx, y: cy-1.28*r)) // smooth round crown
        head.addLine(to: CGPoint(x: cx+0.72*r, y: cy-0.95*r))
        head.addQuadCurve(to: CGPoint(x: cx+0.9*r, y: cy-0.28*r), control: CGPoint(x: cx+0.98*r, y: cy-0.62*r))
        head.addQuadCurve(to: CGPoint(x: cx, y: cy+0.46*r), control: CGPoint(x: cx+0.8*r, y: cy+0.42*r))
        head.addQuadCurve(to: CGPoint(x: cx-0.9*r, y: cy-0.28*r), control: CGPoint(x: cx-0.8*r, y: cy+0.42*r))
        head.closeSubpath()
        cel(g, head, white, cx, cy, r, ol)
        for sx: CGFloat in [-1, 1] { // pink inner ears
            let inr = CGMutablePath()
            inr.move(to: CGPoint(x: cx+sx*0.45*r, y: cy-1.44*r)); inr.addLine(to: CGPoint(x: cx+sx*0.34*r, y: cy-1.04*r)); inr.addLine(to: CGPoint(x: cx+sx*0.6*r, y: cy-1.02*r)); inr.closeSubpath()
            g.addPath(inr); g.setFillColor(pink.withAlphaComponent(0.8).cgColor); g.fillPath()
        }
        let beard = furBlob(cx, cy+0.08*r, 0.85*r, 0.55*r, 9, 0.1*r)
        g.addPath(beard); g.setFillColor(white.cgColor); g.fillPath(); g.addPath(beard); g.setStrokeColor(ol.cgColor); g.setLineWidth(1); g.strokePath()
        // face
        let eyeY = cy-0.5*r, eDX = 0.34*r, er = 0.13*r, lw = max(1, 0.05*r)
        eyes(g, cx, eyeY, eDX, er, r, state: state, blink: blink, iris: nil)
        if state != "dead" {
            g.setFillColor(nose.cgColor); g.fillEllipse(in: CGRect(x: cx-0.17*r, y: cy-0.3*r, width: 0.34*r, height: 0.26*r))
        }
        // mouth / tongue per state
        switch state {
        case "healthy", "party":
            g.setStrokeColor(nose.cgColor); g.setLineWidth(lw); g.setLineCap(.round)
            g.move(to: CGPoint(x: cx, y: cy-0.04*r)); g.addLine(to: CGPoint(x: cx, y: cy+0.06*r)); g.strokePath()
            g.setFillColor(nose.cgColor); g.addPath(CGPath(roundedRect: CGRect(x: cx-0.18*r, y: cy+0.06*r, width: 0.36*r, height: 0.18*r), cornerWidth: 0.08*r, cornerHeight: 0.08*r, transform: nil)); g.fillPath()
            g.setFillColor(rgb(0xE8909E).cgColor); g.addPath(CGPath(roundedRect: CGRect(x: cx-0.1*r, y: cy+0.13*r, width: 0.2*r, height: 0.27*r), cornerWidth: 0.09*r, cornerHeight: 0.09*r, transform: nil)); g.fillPath()
            g.setStrokeColor(darken(rgb(0xE8909E), 0.22).cgColor); g.setLineWidth(1); g.move(to: CGPoint(x: cx, y: cy+0.19*r)); g.addLine(to: CGPoint(x: cx, y: cy+0.37*r)); g.strokePath()
        case "danger": g.setFillColor(nose.cgColor); g.fillEllipse(in: CGRect(x: cx-0.09*r, y: cy+0.05*r, width: 0.18*r, height: 0.15*r)); sweat(g, cx+0.82*r, cy-0.5*r, r)
        case "caution": mouthCurve(g, cx, cy+0.1*r, 0.14*r, -0.04*r, lw); sweat(g, cx+0.82*r, cy-0.5*r, r)
        case "sleep": zMark(g, cx+0.78*r, cy-1.0*r, r)
        default: break
        }
    }

    // MARK: 👻 ghost — translucent

    private static func drawGhost(_ g: CGContext, _ n: CGFloat, _ state: String, _ blink: Bool) {
        let cx = n/2, cy = n/2, r = n*0.30
        let pale = rgb(0xF4F4FC)
        for (k, alpha): (CGFloat, CGFloat) in [(1.75, 0.05), (1.4, 0.07)] {
            g.setFillColor(pale.withAlphaComponent(alpha).cgColor); g.fillEllipse(in: CGRect(x: cx-k*r, y: cy-k*r, width: 2*k*r, height: 2*k*r))
        }
        g.setFillColor(rgb(0x9FB6E0, 0.5).cgColor); g.fillEllipse(in: CGRect(x: cx-0.2*r, y: cy+0.25*r, width: 0.5*r, height: 0.5*r))
        g.setFillColor(rgb(0xC9A8D8, 0.45).cgColor); g.fillEllipse(in: CGRect(x: cx+0.42*r, y: cy-0.42*r, width: 0.36*r, height: 0.36*r))
        let body = CGMutablePath()
        let w = 1.02*r, top = cy-0.95*r, bottom = cy+0.95*r
        body.move(to: CGPoint(x: cx-w, y: cy)); body.addQuadCurve(to: CGPoint(x: cx, y: top), control: CGPoint(x: cx-w, y: top)); body.addQuadCurve(to: CGPoint(x: cx+w, y: cy), control: CGPoint(x: cx+w, y: top)); body.addLine(to: CGPoint(x: cx+w, y: bottom-0.18*r))
        let seg = 2*w/3
        for i in 0..<3 { let x0 = cx+w-CGFloat(i)*seg; body.addQuadCurve(to: CGPoint(x: x0-seg, y: bottom-0.18*r), control: CGPoint(x: x0-seg/2, y: bottom+0.22*r)) }
        body.closeSubpath()
        let dead = state == "dead"
        if dead { // soul gone — hollow outline
            g.addPath(body); g.setStrokeColor(pale.withAlphaComponent(0.6).cgColor); g.setLineWidth(1.4); g.strokePath()
        } else {
            g.saveGState(); g.addPath(body); g.clip()
            g.setFillColor(pale.withAlphaComponent(0.34).cgColor); g.fill(CGRect(x: cx-2*r, y: cy-2*r, width: 4*r, height: 4*r))
            g.setFillColor(NSColor.white.withAlphaComponent(0.22).cgColor); g.fill(CGRect(x: cx-2*r, y: cy-1.6*r, width: 4*r, height: 1.3*r))
            g.setFillColor(rgb(0x14141C, 0.18).cgColor); g.fill(CGRect(x: cx-2*r, y: cy+0.4*r, width: 4*r, height: 1.6*r))
            g.restoreGState()
            g.addPath(body); g.setStrokeColor(NSColor.white.withAlphaComponent(0.7).cgColor); g.setLineWidth(1.4); g.strokePath()
        }
        // face
        let eyeY = cy-0.3*r, eDX = 0.4*r, er = 0.15*r, lw = max(1, 0.05*r)
        let soft = rgb(0x3A3A4A)
        if blink || state == "sleep" { eyeClosed(g, cx-eDX, eyeY, er, lw); eyeClosed(g, cx+eDX, eyeY, er, lw) }
        else {
            switch state {
            case "dead": eyeX(g, cx-eDX, eyeY, er*0.85, lw); eyeX(g, cx+eDX, eyeY, er*0.85, lw)
            case "party": eyeHappy(g, cx-eDX, eyeY, er, lw); eyeHappy(g, cx+eDX, eyeY, er, lw)
            default:
                g.setFillColor(soft.withAlphaComponent(0.85).cgColor)
                g.fillEllipse(in: CGRect(x: cx-eDX-er*0.6, y: eyeY-er*0.9, width: er*1.2, height: er*1.7))
                g.fillEllipse(in: CGRect(x: cx+eDX-er*0.6, y: eyeY-er*0.9, width: er*1.2, height: er*1.7))
            }
        }
        switch state {
        case "danger": g.setFillColor(soft.withAlphaComponent(0.85).cgColor); g.fillEllipse(in: CGRect(x: cx-0.13*r, y: cy+0.1*r, width: 0.26*r, height: 0.26*r)) // scream
        case "caution": mouthCurve(g, cx, cy+0.18*r, 0.14*r, -0.06*r, lw)
        default: break
        }
        if !dead {
            g.setFillColor(pink.withAlphaComponent(0.3).cgColor)
            g.fillEllipse(in: CGRect(x: cx-0.6*r, y: cy+0.02*r, width: 0.24*r, height: 0.14*r)); g.fillEllipse(in: CGRect(x: cx+0.36*r, y: cy+0.02*r, width: 0.24*r, height: 0.14*r))
        }
    }
}

/// Renders the pet for a given animation frame. Prefers a bundled illustration
/// asset (`pets/<character>-<state>.png`) and falls back to the procedural pet.
/// The frame counter lives in the parent HUD view so pet playback stays aligned
/// with the rest of the card.
struct PetSpriteView: View {
    let style: String
    let state: String
    let size: CGFloat
    let frame: Int
    /// Reports the behavior now playing (idle/stretch/walk/excited/…) so callers
    /// can place the cat's words where her pose implies (above when she perks up,
    /// to the side on a walk, by her head as a thought when she's calm).
    var onBehavior: ((String) -> Void)? = nil

    // Behavior scheduler. The pet mostly RESTS — it holds a still frame (just a soft
    // breath) for a dwell, then plays one short take (usually a small idle look-
    // around, occasionally a state-appropriate action), then settles back to rest.
    // So it's still most of the time, not animating non-stop. Crucially, rest HOLDS
    // the take's OWN final frame — so a clip freezes seamlessly into its rest (no
    // dissolve, no snap to a different pose). The only cut is when rest ends and the
    // next take begins; that cut is hidden by the new take's motion (cut-on-action).
    @State private var group = "·rest"    // behavior now playing (or ·rest = resting)
    @State private var cur = 0            // take index within the group
    @State private var start = Int.min    // clock frame this take began
    @State private var restUntil = Int.min // resting until this clock frame
    @State private var restG = "idle"     // while resting, hold this frame: group,
    @State private var restC = 0          //   take index,
    @State private var restI = 0          //   and frame (the last take's final frame)
    private static let restGroup = "·rest"
    @State private var armed = false

    // Actions ping-pong (play, then reverse back to their resting pose) so they
    // settle naturally and end ON that pose; idle plays STRAIGHT — reversing a lively
    // idle (a dog un-leaning, fur un-settling) reads as the video rewinding.
    private static let actionGroups: Set<String> = ["stretch", "loaf", "lie", "walk", "pace", "excited", "play", "jump"]
    private func isAction(_ g: String) -> Bool { Self.actionGroups.contains(g) }

    // Playback rate off the 20 fps clock. Brisk by default so a gentle clip never
    // feels frozen; slowed right down when the quota's gone so the cat reads as
    // drowsy/resting.
    private func playFps(_ g: String, _ state: String) -> Double {
        if state == "dead" { return 7 }            // dozing
        if state == "danger" { return 9 }          // subdued
        switch g {
        case "excited", "play", "jump": return 11  // let the stand-up breathe
        default:                        return 12
        }
    }

    /// Per quota-state behavior design: when a rest ends, `p` = chance the next take
    /// is a real action (vs. a small idle look-around); `pool` = which actions are
    /// appropriate (with weights). Only groups that actually have assets survive the
    /// filter, so this degrades gracefully. Kept low so the pet stays mostly still —
    /// the rest dwell (restDwell) is what makes it idle most of the time.
    ///   healthy → calm & content (rare stretch / walk) — NEVER the excited
    ///             bounce; that's a refill-only reward.
    ///   caution → a touch more alert (looks around).
    ///   danger  → tired, settles into a loaf.
    ///   dead    → resting / dozing, slowed way down, with a drifting "z".
    ///   party   → celebrating (excited / jump).
    private func behaviorPlan(_ state: String) -> (p: Double, pool: [String: Int]) {
        switch state {
        case "party":   return (1.0,  ["excited": 3, "jump": 2, "play": 2])
        case "healthy": return (0.22, ["stretch": 3, "walk": 1])
        case "caution": return (0.28, ["walk": 3, "stretch": 2])
        case "danger":  return (0.35, ["loaf": 4, "lie": 2, "stretch": 1])
        case "dead":    return (0.40, ["loaf": 2, "lie": 1])
        default:        return (0.20, ["stretch": 2, "walk": 1])
        }
    }

    /// How long to hold the resting pose before the next take, in 20 fps clock
    /// frames. Long by default so the pet reads as calm/still; quick when partying.
    private func restDwell() -> Int {
        let sec: ClosedRange<Double>
        switch state {
        case "party":   sec = 0.5 ... 1.4
        case "dead":    sec = 6.0 ... 12.0
        case "danger":  sec = 5.0 ... 10.0
        case "caution": sec = 4.5 ... 9.0
        default:        sec = 5.0 ... 11.0   // healthy
        }
        return Int(Double.random(in: sec) * 20)
    }

    private func weightedPick(_ pool: [String: Int]) -> String? {
        let total = pool.values.reduce(0, +)
        guard total > 0 else { return pool.keys.first }
        var r = Int.random(in: 0 ..< total)
        for (g, w) in pool { r -= w; if r < 0 { return g } }
        return pool.keys.first
    }

    var body: some View {
        let groups = PetImage.groups(style: style)
        Group {
            if !groups.isEmpty {
                animated(groups)
            } else if let img = PetImage.load(style: style) {
                staticBob(img)
            } else {
                Image(nsImage: PixelPet.sprite(style: style, state: state, grid: Int(size), frame: frame))
                    .resizable()
                    .interpolation(.none)
                    .frame(width: size, height: size)
            }
        }
        .onChange(of: frame) { _ in tick(groups) }
        .onChange(of: style) { _ in armStart(groups) }   // character swapped in place → restart cleanly
        .onAppear { if !armed { armStart(groups) } }
    }

    // Index within a take. Actions ping-pong (0…n-1…0) back to their resting frame;
    // idle plays straight through. Either way `tick` records the exact frame showing
    // when the switch fires and `animated` crossfades from it — so there's no cut.
    private func frameIndex(_ played: Int, count n: Int, action: Bool) -> Int {
        guard n > 1 else { return 0 }
        if action, n > 2 {
            let period = 2 * n - 2
            let t = ((played % period) + period) % period
            return t < n ? t : period - t
        }
        return min(played, n - 1)
    }

    private func takeLength(count n: Int, action: Bool) -> Int { (action && n > 2) ? (2 * n - 2) : n }

    @ViewBuilder private func animated(_ groups: [String]) -> some View {
        let isRest = (group == Self.restGroup)
        // While resting, hold the last take's final frame; otherwise show the take.
        let clips = PetImage.clips(style: style, group: isRest ? restG : group)
        if clips.isEmpty {
            if let img = PetImage.load(style: style) { staticBob(img) }
        } else {
            let clip = clips[min(isRest ? restC : cur, clips.count - 1)]
            let played = armed ? Int(Double(frame - start) * playFps(group, state) / 20.0) : 0
            let idx = isRest ? min(restI, clip.count - 1)
                             : frameIndex(played, count: clip.count, action: isAction(group))
            let dozing = (state == "dead")
            // No idle bob — when the pet is resting it stays genuinely still (the
            // bob read as the pet floating up and down). Motion only ever comes from
            // the clip frames themselves.
            ZStack {
                Image(nsImage: clip[idx])
                    .resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                if dozing { zzz() }
            }
            .opacity(dozing ? 0.94 : 1)
        }
    }

    @ViewBuilder private func zzz() -> some View {
        // A single sleepy "z" drifting up and fading, every ~4.5s.
        let cycle = 90
        let t = Double(frame % cycle) / Double(cycle)
        Text("z")
            .font(.system(size: size * 0.17, weight: .heavy, design: .rounded))
            .foregroundColor(.white.opacity(0.42 * (1 - t)))
            .offset(x: size * 0.25, y: -size * 0.24 - CGFloat(t) * size * 0.16)
            .allowsHitTesting(false)
    }

    @ViewBuilder private func staticBob(_ img: NSImage) -> some View {
        // Static illustration: gentle floating bob (no squash — a polished
        // illustration shouldn't deform like the procedural blob).
        let phase = 2 * Double.pi * Double(frame) / Double(PixelPet.animationFrames)
        let bob = CGFloat(sin(phase)) * size * 0.012
        Image(nsImage: img)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .offset(y: bob)
    }

    private func armStart(_ groups: [String]) {
        let base = groups.contains("idle") ? "idle" : (groups.first ?? "idle")
        group = Self.restGroup; cur = 0; start = frame
        restG = base; restC = 0; restI = 0          // first impression: the initial pose
        restUntil = frame + restDwell()
        armed = true
        onBehavior?(base)
    }

    private func tick(_ groups: [String]) {
        guard !groups.isEmpty else { return }
        if !armed { armStart(groups); return }
        let base = groups.contains("idle") ? "idle" : (groups.first ?? "idle")

        // Resting: hold the last take's final frame until the dwell elapses, then
        // start the next take (its own motion hides the cut into it).
        if group == Self.restGroup {
            guard frame >= restUntil else { return }
            let (ng, nc) = chooseNext(groups: groups)
            group = ng; cur = nc; start = frame
            onBehavior?(ng)
            return
        }

        // A take is playing: when its motion finishes, freeze on its final frame and
        // hold there as the rest — seamless, no dissolve, no snap to a different pose.
        let clips = PetImage.clips(style: style, group: group)
        guard !clips.isEmpty else { return }
        let clip = clips[min(cur, clips.count - 1)]
        let action = isAction(group)
        let played = Int(Double(frame - start) * playFps(group, state) / 20.0)
        if played >= takeLength(count: clip.count, action: action) {
            restG = group
            restC = min(cur, clips.count - 1)
            restI = action ? 0 : (clip.count - 1)   // action settled back to rest(0); idle ended on last
            group = Self.restGroup
            restUntil = frame + restDwell()
            onBehavior?(base)
        }
    }

    /// Pick the take to play when a rest ends: usually a small idle look-around,
    /// occasionally a state-appropriate action (see behaviorPlan). The pet always
    /// returns to rest afterward.
    private func chooseNext(groups: [String]) -> (String, Int) {
        let base = groups.contains("idle") ? "idle" : (groups.first ?? "idle")
        func pick(_ g: String) -> (String, Int) {
            let n = max(1, PetImage.clips(style: style, group: g).count)
            return (g, n <= 1 ? 0 : Int.random(in: 0 ..< n))
        }
        let plan = behaviorPlan(state)
        let pool = plan.pool.filter { groups.contains($0.key) }
        if !pool.isEmpty, Double.random(in: 0 ..< 1) < plan.p, let g = weightedPick(pool) {
            return pick(g)                          // a state-appropriate action
        }
        return pick(base)                           // otherwise a gentle idle take
    }
}
