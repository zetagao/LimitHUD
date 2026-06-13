import AppKit
import SwiftUI

/// Fine-mosaic quota pet, rendered procedurally onto a small pixel grid
/// (AA off, 2-tone cel shading, 1px outline) — no image assets.
/// Styles: mochi (blob) / neko (cat) / boo (ghost) / inu (dog).
/// Morandi palette; each character expresses every state its own way.
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

    /// One full idle-animation loop, in frames (played at ~20 fps → ~3.5s).
    /// Long and calm on purpose — slow breathing with occasional, spaced beats.
    static let animationFrames = 70

    static func sprite(style: String, state: String, grid: Int, frame: Int = 0) -> NSImage {
        let f = ((frame % animationFrames) + animationFrames) % animationFrames
        let key = "\(style)/\(state)/\(grid)/\(f)"
        if let img = cache[key] { return img }
        let img = render(style: style, state: state, grid: grid, frame: f)
        cache[key] = img
        return img
    }

    /// Scripted expression timeline within a loop — when the pet winks, glances,
    /// darts its eyes, etc. Returns the pose index the face switch understands.
    private static func scheduledPose(_ state: String, _ f: Int) -> Int {
        switch state {
        case "healthy": // mostly calm; one wink, a held content-squint, a sparkle glance
            if (22...30).contains(f) { return 2 } // wink
            if (42...52).contains(f) { return 1 } // content squint (held, calm)
            if (60...66).contains(f) { return 3 } // glance + sparkle
            return 0
        case "caution": // a long, sustained glance away, then back
            if (16...38).contains(f) { return 1 }
            if (52...64).contains(f) { return 2 }
            return 0
        case "danger": // nervous — a couple of slow looks, not a buzz
            if (12...26).contains(f) { return 1 }
            if (40...54).contains(f) { return 2 }
            return 0
        case "party": return (f / 18) % 3
        case "sleep": return (f / 35) % 2
        default:      return 0
        }
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

    private static let dark = rgb(0x2A2A2E)
    /// Morandi-leaning but readable: gray undertone, states clearly apart.
    private static let palettes: [String: NSColor] = [
        "healthy": rgb(0x8FB573), "caution": rgb(0xDCA254), "danger": rgb(0xC75555),
        "dead": rgb(0x6E6C75), "sleep": rgb(0x6E6C75), "party": rgb(0x8FB573),
    ]
    private static let blushColor = rgb(0xDB9C9C, 0.65)
    private static let sweatColor = rgb(0x7FB5D6, 0.95)
    private static let haloColor  = rgb(0xDCC06E)
    private static let tongueColor = rgb(0xDB9C9C)
    private static let confetti = [rgb(0xCC7F7E), rgb(0xDCC06E), rgb(0x7FA8C4), rgb(0xAE8FC9), rgb(0x8FB573)]

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
        let n = CGFloat(N)
        draw(g, style: style, state: state, cx: n/2, cy: n/2 + n*0.04, r: n*0.30, frame: frame)
        NSGraphicsContext.current = saved
        let img = NSImage(size: NSSize(width: N, height: N))
        img.addRepresentation(rep)
        return img
    }

    // swiftlint:disable:next function_body_length
    private static func draw(_ g: CGContext, style: String, state: String,
                             cx: CGFloat, cy: CGFloat, r: CGFloat, frame: Int) {
        let base = palettes[state] ?? palettes["healthy"]!
        let isDead = state == "dead", isParty = state == "party"
        let outline = darken(base, 0.48)
        // ghost dies hollow; everything is drawn as outlines from here
        let hollow = isDead && style == "boo"
        // mochi dies as a puddle: face sits low, no body above
        let puddle = isDead && style == "mochi"

        // ── idle animation (continuous, frame-driven) ──
        let loop = animationFrames
        let f = ((frame % loop) + loop) % loop
        let a = 2 * Double.pi * Double(f) / Double(loop)
        let pose = scheduledPose(state, f)
        let blink = !isDead && !isParty && (f == loop - 3 || f == loop - 2)
        // Squash & stretch + bob, tuned per mood. Anchored at the feet so the
        // body "breathes" off the ground rather than scaling about its center.
        var sx: CGFloat = 1, sy: CGFloat = 1, dx: CGFloat = 0, dy: CGFloat = 0
        let baseY = cy + r * 0.92
        if !isDead {
            switch state {
            case "party": // springy double hop
                let hh = CGFloat(abs(sin(a)))
                dy = -0.13 * r * hh
                sy = 1 + 0.10 * hh - 0.08 * (1 - hh)
                sx = 1 - 0.10 * hh + 0.08 * (1 - hh)
            case "danger": // gentle breath + a soft nervous sway (not a buzz)
                let br = CGFloat(sin(a))
                sy = 1 + 0.035 * br; sx = 1 - 0.03 * br
                dx = 0.02 * r * CGFloat(sin(a * 4))
                dy = 0.025 * r * CGFloat(cos(a))
            case "sleep": // slow deep breathing
                let br = CGFloat(sin(a))
                sy = 1 + 0.08 * br; sx = 1 - 0.06 * br
                dy = 0.03 * r * CGFloat(cos(a))
            default: // healthy / caution — gentle breathing bob
                let br = CGFloat(sin(a))
                sy = 1 + 0.05 * br; sx = 1 - 0.04 * br
                dy = 0.05 * r * CGFloat(cos(a))
            }
        }

        func fillBody(_ path: CGPath) {
            if hollow {
                g.addPath(path)
                g.setStrokeColor(base.cgColor)
                g.setLineWidth(1)
                g.strokePath()
                return
            }
            g.saveGState()
            g.addPath(path); g.clip()
            g.setFillColor(base.cgColor)
            g.fill(CGRect(x: cx - 2*r, y: cy - 2*r, width: 4*r, height: 4*r))
            g.setFillColor(lighten(base, 0.22).cgColor)
            g.fill(CGRect(x: cx - 2*r, y: cy - 2*r, width: 4*r, height: 2*r - 0.5*r))
            g.restoreGState()
            g.addPath(path)
            g.setStrokeColor(outline.cgColor)
            g.setLineWidth(1)
            g.strokePath()
        }

        // Apply the breathing/bob/hop transform to the whole pet.
        g.saveGState()
        g.translateBy(x: cx + dx, y: baseY + dy)
        g.scaleBy(x: sx, y: sy)
        g.translateBy(x: -cx, y: -baseY)

        // ── body (shape itself can react to the state) ──
        switch style {
        case "mochi":
            if puddle {
                // melted flat
                fillBody(CGPath(roundedRect: CGRect(x: cx - 1.3*r, y: cy + 0.15*r, width: 2.6*r, height: 0.8*r),
                                cornerWidth: 0.4*r, cornerHeight: 0.4*r, transform: nil))
            } else if state == "danger" {
                // starting to slump: wider + shorter
                fillBody(CGPath(roundedRect: CGRect(x: cx - 1.18*r, y: cy - 0.70*r, width: 2.36*r, height: 1.72*r),
                                cornerWidth: 0.80*r, cornerHeight: 0.80*r, transform: nil))
            } else if isParty {
                // jump squash & stretch: taller
                fillBody(CGPath(roundedRect: CGRect(x: cx - 0.95*r, y: cy - 1.10*r, width: 1.9*r, height: 2.1*r),
                                cornerWidth: 0.85*r, cornerHeight: 0.85*r, transform: nil))
            } else {
                fillBody(CGPath(roundedRect: CGRect(x: cx - 1.05*r, y: cy - 0.92*r, width: 2.1*r, height: 1.95*r),
                                cornerWidth: 0.88*r, cornerHeight: 0.88*r, transform: nil))
            }
        case "neko":
            // ears react: flat back when scared, droopy when dead
            let flat = state == "danger" || isDead
            for sx in [CGFloat(-1), 1] {
                let ear = CGMutablePath()
                if flat {
                    ear.move(to: CGPoint(x: cx + sx*0.32*r, y: cy - 0.70*r))
                    ear.addLine(to: CGPoint(x: cx + sx*1.10*r, y: cy - 0.86*r))
                    ear.addLine(to: CGPoint(x: cx + sx*0.94*r, y: cy - 0.40*r))
                } else {
                    ear.move(to: CGPoint(x: cx + sx*0.30*r, y: cy - 0.78*r))
                    ear.addLine(to: CGPoint(x: cx + sx*0.78*r, y: cy - 1.42*r))
                    ear.addLine(to: CGPoint(x: cx + sx*0.92*r, y: cy - 0.52*r))
                }
                ear.closeSubpath()
                g.addPath(ear); g.setFillColor(base.cgColor); g.fillPath()
                g.addPath(ear); g.setStrokeColor(outline.cgColor); g.setLineWidth(1); g.strokePath()
                if !flat {
                    let inner = CGMutablePath()
                    inner.move(to: CGPoint(x: cx + sx*0.48*r, y: cy - 0.84*r))
                    inner.addLine(to: CGPoint(x: cx + sx*0.74*r, y: cy - 1.20*r))
                    inner.addLine(to: CGPoint(x: cx + sx*0.82*r, y: cy - 0.64*r))
                    inner.closeSubpath()
                    g.addPath(inner); g.setFillColor(rgb(0xD9A5A5, isDead ? 0.4 : 0.9).cgColor); g.fillPath()
                }
            }
            fillBody(CGPath(ellipseIn: CGRect(x: cx - 1.02*r, y: cy - 0.95*r, width: 2.04*r, height: 1.9*r), transform: nil))
            g.setStrokeColor(outline.cgColor); g.setLineWidth(1); g.setLineCap(.butt)
            for sx in [CGFloat(-1), 1] {
                for dy in [CGFloat(0.10), 0.30] {
                    g.move(to: CGPoint(x: cx + sx*0.98*r, y: cy + dy*r))
                    g.addLine(to: CGPoint(x: cx + sx*1.38*r, y: cy + (dy - 0.06)*r))
                    g.strokePath()
                }
            }
            if isParty { // paws up!
                for sx in [CGFloat(-1), 1] {
                    let paw = CGRect(x: cx + sx*0.92*r - 0.17*r, y: cy - 0.25*r, width: 0.34*r, height: 0.30*r)
                    g.setFillColor(base.cgColor); g.fillEllipse(in: paw)
                    g.setStrokeColor(outline.cgColor); g.setLineWidth(1); g.strokeEllipse(in: paw)
                }
            }
            if isDead { // halo
                g.setStrokeColor(haloColor.cgColor); g.setLineWidth(max(1, 0.06*r))
                g.strokeEllipse(in: CGRect(x: cx - 0.38*r, y: cy - 1.62*r, width: 0.76*r, height: 0.24*r))
            }
        case "inu":
            // ears: perk up at party, droop further as things get worse
            let earAngle: CGFloat, earLift: CGFloat
            switch state {
            case "party":  earAngle = 0.06; earLift = -0.42*r
            case "caution": earAngle = 0.42; earLift = 0.06*r
            case "danger", "dead": earAngle = 0.62; earLift = 0.14*r
            default: earAngle = 0.30; earLift = 0
            }
            for sx in [CGFloat(-1), 1] {
                g.saveGState()
                g.translateBy(x: cx + sx*0.88*r, y: cy - 0.30*r + earLift)
                g.rotate(by: sx * earAngle)
                let ear = CGPath(roundedRect: CGRect(x: -0.26*r, y: -0.55*r, width: 0.52*r, height: 1.05*r),
                                 cornerWidth: 0.26*r, cornerHeight: 0.26*r, transform: nil)
                g.addPath(ear); g.setFillColor(darken(base, 0.18).cgColor); g.fillPath()
                g.addPath(ear); g.setStrokeColor(outline.cgColor); g.setLineWidth(1); g.strokePath()
                g.restoreGState()
            }
            fillBody(CGPath(ellipseIn: CGRect(x: cx - 1.02*r, y: cy - 0.95*r, width: 2.04*r, height: 1.9*r), transform: nil))
            g.setFillColor(lighten(base, 0.32).cgColor)
            g.fillEllipse(in: CGRect(x: cx - 0.40*r, y: cy + 0.14*r, width: 0.80*r, height: 0.55*r))
            g.setFillColor(dark.cgColor)
            g.fillEllipse(in: CGRect(x: cx - 0.11*r, y: cy + 0.18*r, width: 0.22*r, height: 0.16*r))
        default: // boo (ghost)
            let body = CGMutablePath()
            let w = 1.02*r, top = cy - 0.95*r, bottom = cy + 0.92*r
            body.move(to: CGPoint(x: cx - w, y: cy))
            body.addQuadCurve(to: CGPoint(x: cx, y: top), control: CGPoint(x: cx - w, y: top))
            body.addQuadCurve(to: CGPoint(x: cx + w, y: cy), control: CGPoint(x: cx + w, y: top))
            body.addLine(to: CGPoint(x: cx + w, y: bottom - 0.18*r))
            let seg = 2*w / 3
            for i in 0..<3 {
                let x0 = cx + w - CGFloat(i)*seg
                body.addQuadCurve(to: CGPoint(x: x0 - seg, y: bottom - 0.18*r),
                                  control: CGPoint(x: x0 - seg/2, y: bottom + 0.22*r))
            }
            body.closeSubpath()
            fillBody(body)
            if state == "danger" { // shaking
                g.setStrokeColor(base.withAlphaComponent(0.7).cgColor)
                g.setLineWidth(1)
                for sx in [CGFloat(-1), 1] {
                    g.move(to: CGPoint(x: cx + sx*1.22*r, y: cy - 0.25*r))
                    g.addLine(to: CGPoint(x: cx + sx*1.34*r, y: cy - 0.05*r))
                    g.strokePath()
                    g.move(to: CGPoint(x: cx + sx*1.30*r, y: cy + 0.22*r))
                    g.addLine(to: CGPoint(x: cx + sx*1.18*r, y: cy + 0.42*r))
                    g.strokePath()
                }
            }
        }

        // ── face ──
        var eyeY = cy - 0.12*r
        let eyeDX = 0.42*r, eyeR = 0.20*r
        var mouthY = cy + 0.38*r
        if puddle { eyeY = cy + 0.42*r; mouthY = cy + 0.70*r }
        let stroke = max(1.0, 0.07*r)
        let faceInk = hollow ? base : dark

        func glossyEye(_ ex: CGFloat, w: CGFloat = 1) {
            g.setFillColor(faceInk.cgColor)
            g.fillEllipse(in: CGRect(x: ex - eyeR*w, y: eyeY - eyeR*1.15, width: eyeR*2*w, height: eyeR*2.3))
            g.setFillColor(NSColor.white.cgColor)
            g.fillEllipse(in: CGRect(x: ex + eyeR*0.05*w, y: eyeY - eyeR*0.85, width: eyeR*0.62*w, height: eyeR*0.62))
            g.fillEllipse(in: CGRect(x: ex - eyeR*0.45*w, y: eyeY + eyeR*0.35, width: eyeR*0.3, height: eyeR*0.3))
        }
        /// Plain little oval eyes — Boo's timid blank look.
        func dotEye(_ ex: CGFloat) {
            g.setFillColor(faceInk.cgColor)
            g.fillEllipse(in: CGRect(x: ex - eyeR*0.55, y: eyeY - eyeR*0.8, width: eyeR*1.1, height: eyeR*1.6))
            g.setFillColor(NSColor.white.withAlphaComponent(0.9).cgColor)
            g.fillEllipse(in: CGRect(x: ex - eyeR*0.12, y: eyeY - eyeR*0.5, width: eyeR*0.35, height: eyeR*0.35))
        }
        /// White sclera, pupils shifted aside — Neko's unimpressed side-eye.
        func sideEye(_ ex: CGFloat) {
            let er = CGRect(x: ex - eyeR*0.95, y: eyeY - eyeR*1.05, width: eyeR*1.9, height: eyeR*2.1)
            g.setFillColor(NSColor.white.cgColor); g.fillEllipse(in: er)
            g.setStrokeColor(faceInk.cgColor); g.setLineWidth(1); g.strokeEllipse(in: er)
            g.setFillColor(faceInk.cgColor)
            g.fillEllipse(in: CGRect(x: ex - eyeR*0.85, y: eyeY - eyeR*0.35, width: eyeR*0.8, height: eyeR*0.95))
        }
        /// Huge sclera, pinprick pupil — terror.
        func shockEye(_ ex: CGFloat) {
            let er = CGRect(x: ex - eyeR*1.05, y: eyeY - eyeR*1.15, width: eyeR*2.1, height: eyeR*2.3)
            g.setFillColor(NSColor.white.cgColor); g.fillEllipse(in: er)
            g.setStrokeColor(faceInk.cgColor); g.setLineWidth(1); g.strokeEllipse(in: er)
            g.setFillColor(faceInk.cgColor)
            g.fillEllipse(in: CGRect(x: ex - eyeR*0.28, y: eyeY - eyeR*0.25, width: eyeR*0.55, height: eyeR*0.6))
        }
        /// >.< squeezed-shut eyes (dir: chevron apex points toward face center).
        func squeezeEye(_ ex: CGFloat, _ dir: CGFloat) {
            g.setStrokeColor(faceInk.cgColor)
            g.setLineWidth(stroke*1.1); g.setLineCap(.round)
            let a = eyeR*0.8
            g.move(to: CGPoint(x: ex - dir*a, y: eyeY - a))
            g.addLine(to: CGPoint(x: ex + dir*a*0.5, y: eyeY))
            g.addLine(to: CGPoint(x: ex - dir*a, y: eyeY + a))
            g.strokePath()
        }
        /// Glossy eyes + inner-raised brows — puppy pleading.
        func pleadEye(_ ex: CGFloat, _ dir: CGFloat) {
            glossyEye(ex)
            g.setStrokeColor(faceInk.cgColor)
            g.setLineWidth(stroke); g.setLineCap(.round)
            let a = eyeR
            g.move(to: CGPoint(x: ex - dir*a, y: eyeY - a*1.45))
            g.addLine(to: CGPoint(x: ex + dir*a*0.6, y: eyeY - a*1.85))
            g.strokePath()
        }
        func closedEye(_ ex: CGFloat) {
            g.setStrokeColor(faceInk.cgColor)
            g.setLineWidth(stroke*1.2); g.setLineCap(.round)
            g.move(to: CGPoint(x: ex - eyeR*0.9, y: eyeY))
            g.addLine(to: CGPoint(x: ex + eyeR*0.9, y: eyeY))
            g.strokePath()
        }
        func halfLidEye(_ ex: CGFloat) {
            glossyEye(ex)
            g.setFillColor(lighten(base, 0.22).cgColor)
            g.fill(CGRect(x: ex - eyeR*1.2, y: eyeY - eyeR*1.3, width: eyeR*2.4, height: eyeR*1.1))
            g.setStrokeColor(faceInk.cgColor); g.setLineWidth(stroke)
            g.move(to: CGPoint(x: ex - eyeR, y: eyeY - eyeR*0.2))
            g.addLine(to: CGPoint(x: ex + eyeR, y: eyeY - eyeR*0.2))
            g.strokePath()
        }
        func xEye(_ ex: CGFloat) {
            g.setStrokeColor(faceInk.cgColor)
            g.setLineWidth(stroke); g.setLineCap(.round)
            let a = eyeR*0.8
            g.move(to: CGPoint(x: ex - a, y: eyeY - a)); g.addLine(to: CGPoint(x: ex + a, y: eyeY + a)); g.strokePath()
            g.move(to: CGPoint(x: ex + a, y: eyeY - a)); g.addLine(to: CGPoint(x: ex - a, y: eyeY + a)); g.strokePath()
        }
        func happyEye(_ ex: CGFloat) {
            g.setStrokeColor(faceInk.cgColor)
            g.setLineWidth(stroke*1.2); g.setLineCap(.round)
            let a = eyeR*0.9
            g.move(to: CGPoint(x: ex - a, y: eyeY + a*0.4))
            g.addQuadCurve(to: CGPoint(x: ex + a, y: eyeY + a*0.4),
                           control: CGPoint(x: ex, y: eyeY - a*1.2))
            g.strokePath()
        }
        func smileMouth() {
            g.setStrokeColor(faceInk.cgColor); g.setLineWidth(stroke); g.setLineCap(.round)
            g.move(to: CGPoint(x: cx - 0.20*r, y: mouthY))
            g.addQuadCurve(to: CGPoint(x: cx + 0.20*r, y: mouthY), control: CGPoint(x: cx, y: mouthY + 0.24*r))
            g.strokePath()
        }
        func catMouth() { // ω
            g.setStrokeColor(faceInk.cgColor); g.setLineWidth(stroke); g.setLineCap(.round)
            g.move(to: CGPoint(x: cx - 0.22*r, y: mouthY))
            g.addQuadCurve(to: CGPoint(x: cx, y: mouthY), control: CGPoint(x: cx - 0.11*r, y: mouthY + 0.20*r))
            g.addQuadCurve(to: CGPoint(x: cx + 0.22*r, y: mouthY), control: CGPoint(x: cx + 0.11*r, y: mouthY + 0.20*r))
            g.strokePath()
        }
        func flatMouth() {
            g.setStrokeColor(faceInk.cgColor); g.setLineWidth(stroke); g.setLineCap(.round)
            g.move(to: CGPoint(x: cx - 0.14*r, y: mouthY + 0.05*r))
            g.addLine(to: CGPoint(x: cx + 0.14*r, y: mouthY + 0.05*r))
            g.strokePath()
        }
        func tinyO() {
            g.setFillColor(faceInk.cgColor)
            g.fillEllipse(in: CGRect(x: cx - 0.08*r, y: mouthY, width: 0.16*r, height: 0.14*r))
        }
        func sadMouth() {
            g.setStrokeColor(faceInk.cgColor); g.setLineWidth(stroke); g.setLineCap(.round)
            g.move(to: CGPoint(x: cx - 0.16*r, y: mouthY + 0.10*r))
            g.addQuadCurve(to: CGPoint(x: cx + 0.16*r, y: mouthY + 0.10*r),
                           control: CGPoint(x: cx, y: mouthY - 0.12*r))
            g.strokePath()
        }
        func screamMouth() {
            g.setFillColor(faceInk.cgColor)
            g.fillEllipse(in: CGRect(x: cx - 0.16*r, y: mouthY - 0.06*r, width: 0.32*r, height: 0.30*r))
        }
        func openSmileTongue() {
            let smile = CGMutablePath()
            smile.move(to: CGPoint(x: cx - 0.20*r, y: mouthY - 0.02*r))
            smile.addQuadCurve(to: CGPoint(x: cx + 0.20*r, y: mouthY - 0.02*r),
                               control: CGPoint(x: cx, y: mouthY + 0.34*r))
            smile.closeSubpath()
            g.addPath(smile); g.setFillColor(faceInk.cgColor); g.fillPath()
            g.setFillColor(tongueColor.cgColor)
            g.fill(CGRect(x: cx - 0.07*r, y: mouthY + 0.08*r, width: 0.14*r, height: 0.16*r))
        }
        func sweatDrop(_ sx: CGFloat, _ sy: CGFloat) {
            let drop = CGMutablePath()
            drop.move(to: CGPoint(x: sx, y: sy - 0.18*r))
            drop.addQuadCurve(to: CGPoint(x: sx + 0.11*r, y: sy + 0.10*r), control: CGPoint(x: sx + 0.16*r, y: sy - 0.02*r))
            drop.addQuadCurve(to: CGPoint(x: sx - 0.11*r, y: sy + 0.10*r), control: CGPoint(x: sx, y: sy + 0.26*r))
            drop.addQuadCurve(to: CGPoint(x: sx, y: sy - 0.18*r), control: CGPoint(x: sx - 0.16*r, y: sy - 0.02*r))
            g.addPath(drop); g.setFillColor(sweatColor.cgColor); g.fillPath()
        }
        /// Anime cross-pop anger vein 💢 — Neko's annoyance tell.
        /// Four chevrons pointing inward toward a center.
        func angerMark(_ ax: CGFloat, _ ay: CGFloat) {
            g.setStrokeColor(rgb(0xC75555).cgColor)
            g.setLineWidth(max(1, 0.05*r)); g.setLineCap(.round); g.setLineJoin(.round)
            let u = 0.22*r, t = 0.085*r
            for ang in stride(from: CGFloat(0), to: 2*CGFloat.pi, by: .pi/2) {
                let tipX = ax + cos(ang)*u*0.45, tipY = ay + sin(ang)*u*0.45
                let perp = ang + .pi/2
                let baseX = ax + cos(ang)*u, baseY = ay + sin(ang)*u
                g.move(to: CGPoint(x: baseX + cos(perp)*t, y: baseY + sin(perp)*t))
                g.addLine(to: CGPoint(x: tipX, y: tipY))
                g.addLine(to: CGPoint(x: baseX - cos(perp)*t, y: baseY - sin(perp)*t))
                g.strokePath()
            }
        }
        /// Small motion ticks beside the head — trembling.
        func shiver(_ sx: CGFloat, _ sy: CGFloat) {
            g.setStrokeColor(faceInk.withAlphaComponent(0.7).cgColor)
            g.setLineWidth(1); g.setLineCap(.round)
            g.move(to: CGPoint(x: sx, y: sy)); g.addLine(to: CGPoint(x: sx + 0.10*r, y: sy - 0.10*r)); g.strokePath()
            g.move(to: CGPoint(x: sx, y: sy + 0.18*r)); g.addLine(to: CGPoint(x: sx + 0.10*r, y: sy + 0.08*r)); g.strokePath()
        }

        /// Worried slanted brows above both eyes.
        func worriedBrows() {
            g.setStrokeColor(faceInk.cgColor); g.setLineWidth(stroke); g.setLineCap(.round)
            g.move(to: CGPoint(x: cx - eyeDX - 0.18*r, y: eyeY - 0.42*r))
            g.addLine(to: CGPoint(x: cx - eyeDX + 0.14*r, y: eyeY - 0.55*r)); g.strokePath()
            g.move(to: CGPoint(x: cx + eyeDX + 0.18*r, y: eyeY - 0.42*r))
            g.addLine(to: CGPoint(x: cx + eyeDX - 0.14*r, y: eyeY - 0.55*r)); g.strokePath()
        }
        /// A little ✦ twinkle (healthy "sparkle" pose).
        func sparkle(_ sx: CGFloat, _ sy: CGFloat, _ sz: CGFloat) {
            g.setFillColor(NSColor.white.withAlphaComponent(0.92).cgColor)
            g.fill(CGRect(x: sx - sz*0.12, y: sy - sz*0.5, width: sz*0.24, height: sz))
            g.fill(CGRect(x: sx - sz*0.5, y: sy - sz*0.12, width: sz, height: sz*0.24))
        }
        /// A stylized "z" for the sleeping pose.
        func zMark(_ zx: CGFloat, _ zy: CGFloat, _ zs: CGFloat) {
            g.setStrokeColor(faceInk.withAlphaComponent(0.6).cgColor)
            g.setLineWidth(max(1, 0.04*r)); g.setLineCap(.round); g.setLineJoin(.round)
            g.move(to: CGPoint(x: zx, y: zy))
            g.addLine(to: CGPoint(x: zx + zs, y: zy))
            g.addLine(to: CGPoint(x: zx, y: zy + zs))
            g.addLine(to: CGPoint(x: zx + zs, y: zy + zs))
            g.strokePath()
        }

        switch state {
        case "healthy":
            // 4 idle poses: base · content squint · wink · glance + sparkle
            func healthyBase(_ off: CGFloat) {
                switch style {
                case "neko": glossyEye(cx - eyeDX + off, w: 0.72); glossyEye(cx + eyeDX + off, w: 0.72)
                case "boo":  dotEye(cx - eyeDX + off); dotEye(cx + eyeDX + off)
                default:     glossyEye(cx - eyeDX + off); glossyEye(cx + eyeDX + off)
                }
            }
            if blink {
                closedEye(cx - eyeDX); closedEye(cx + eyeDX)
            } else {
                switch pose {
                case 1: happyEye(cx - eyeDX); happyEye(cx + eyeDX)        // content ^^
                case 2: glossyEye(cx - eyeDX); happyEye(cx + eyeDX)       // wink
                case 3: healthyBase(eyeR * 0.42)                          // glance →
                default: healthyBase(0)
                }
            }
            switch style {
            case "neko": catMouth()
            case "boo":  tinyO()              // timid little :o
            case "inu":  openSmileTongue()    // happy panting by default
            default:     smileMouth()
            }
            if pose == 3 && !blink {
                sparkle(cx + 0.92*r, cy - 0.80*r, 0.26*r)
                sparkle(cx - 0.98*r, cy - 0.46*r, 0.17*r)
            }
        case "caution":
            // 3 poses: base · glance away · glance back (keeps each char's eye shape)
            func cautionBase(_ off: CGFloat) {
                switch style {
                case "neko": sideEye(cx - eyeDX + off); sideEye(cx + eyeDX + off)
                case "boo":  dotEye(cx - eyeDX + off); dotEye(cx + eyeDX + off)
                case "inu":  pleadEye(cx - eyeDX + off, -1); pleadEye(cx + eyeDX + off, 1)
                default:     halfLidEye(cx - eyeDX + off); halfLidEye(cx + eyeDX + off)
                }
            }
            if blink {
                closedEye(cx - eyeDX); closedEye(cx + eyeDX)
            } else {
                switch pose {
                case 1: cautionBase(-eyeR * 0.4)   // glance away
                case 2: cautionBase( eyeR * 0.4)   // glance back
                default: cautionBase(0)
                }
            }
            switch style {
            case "boo": sadMouth()
            default:    flatMouth()
            }
            // Distinct distress tell per character (no shared sweat spam):
            switch style {
            case "mochi": sweatDrop(cx + 0.78*r, cy - 0.62*r)   // sweat = mochi's signature
            case "neko":  angerMark(cx + 0.72*r, cy - 0.74*r)   // annoyed cross-pop
            default: break                                       // boo: sad mouth; inu: puppy eyes
            }
        case "danger":
            // 3 poses: base · dart left · dart right (panicked glancing around)
            func dangerBase(_ off: CGFloat) {
                switch style {
                case "neko": shockEye(cx - eyeDX + off); shockEye(cx + eyeDX + off)
                case "boo":  dotEye(cx - eyeDX + off); dotEye(cx + eyeDX + off)
                case "inu":  squeezeEye(cx - eyeDX, 1); squeezeEye(cx + eyeDX, -1) // >.< (fixed)
                default:     glossyEye(cx - eyeDX + off); glossyEye(cx + eyeDX + off)
                }
            }
            if blink {
                closedEye(cx - eyeDX); closedEye(cx + eyeDX)
            } else {
                switch pose {
                case 1: dangerBase(-eyeR * 0.45)
                case 2: dangerBase( eyeR * 0.45)
                default: dangerBase(0)
                }
            }
            switch style {
            case "neko": tinyO()
            case "boo":  screamMouth()        // wide hollow scream
            case "inu":  tinyO()              // whimper (eyes already >.<)
            default:
                worriedBrows()
                g.setFillColor(faceInk.cgColor)
                g.fillEllipse(in: CGRect(x: cx - 0.13*r, y: mouthY - 0.04*r, width: 0.26*r, height: 0.20*r))
            }
            // Danger distress tell per character:
            switch style {
            case "mochi": sweatDrop(cx - 0.85*r, cy - 0.55*r); sweatDrop(cx + 0.85*r, cy - 0.45*r)
            case "inu":   shiver(cx - 1.18*r, cy - 0.1*r); shiver(cx + 1.08*r, cy - 0.1*r) // trembling
            default: break // neko: shock eyes + flat ears; boo: shaking body lines
            }
        case "dead":
            xEye(cx - eyeDX); xEye(cx + eyeDX)
            flatMouth()
            if style == "inu" { // tongue out, flopped
                g.setFillColor(tongueColor.cgColor)
                g.fill(CGRect(x: cx + 0.10*r, y: mouthY + 0.10*r, width: 0.18*r, height: 0.30*r))
            }
            if style == "mochi" || style == "inu" { // soul leaves the body
                g.setFillColor(NSColor.white.withAlphaComponent(0.30).cgColor)
                g.fillEllipse(in: CGRect(x: cx + 0.95*r, y: cy - 1.25*r, width: 0.34*r, height: 0.24*r))
                g.fillEllipse(in: CGRect(x: cx + 1.18*r, y: cy - 1.52*r, width: 0.22*r, height: 0.16*r))
            }
        case "sleep":
            closedEye(cx - eyeDX); closedEye(cx + eyeDX)
            flatMouth()
            // drifting z's (pose 1 adds a second)
            zMark(cx + 0.78*r, cy - 0.95*r, 0.18*r)
            if pose == 1 { zMark(cx + 1.05*r, cy - 1.32*r, 0.13*r) }
        default: // party — every character celebrates differently
            if style == "boo" { // visor shades
                let band = CGRect(x: cx - 0.72*r, y: eyeY - 0.24*r, width: 1.44*r, height: 0.40*r)
                g.setFillColor(dark.cgColor)
                g.fill(band)
                g.setFillColor(NSColor.white.withAlphaComponent(0.35).cgColor)
                g.fill(CGRect(x: cx - 0.60*r, y: eyeY - 0.16*r, width: 0.28*r, height: 0.10*r))
            } else {
                switch pose {
                case 1: glossyEye(cx - eyeDX); happyEye(cx + eyeDX)   // wink
                case 2: glossyEye(cx - eyeDX); glossyEye(cx + eyeDX)  // wide & excited
                default: happyEye(cx - eyeDX); happyEye(cx + eyeDX)   // ^^
                }
            }
            if style == "neko" {
                catMouth()
            } else {
                let smile = CGMutablePath()
                smile.move(to: CGPoint(x: cx - 0.24*r, y: mouthY - 0.04*r))
                smile.addQuadCurve(to: CGPoint(x: cx + 0.24*r, y: mouthY - 0.04*r), control: CGPoint(x: cx, y: mouthY + 0.40*r))
                smile.closeSubpath()
                g.addPath(smile); g.setFillColor(dark.cgColor); g.fillPath()
            }
            if style == "inu" { // happy panting tongue
                g.setFillColor(tongueColor.cgColor)
                g.fill(CGRect(x: cx - 0.09*r, y: mouthY + 0.16*r, width: 0.18*r, height: 0.28*r))
            }
            if style == "mochi" { // the classic party hat stays mochi's thing
                let hatTop = CGPoint(x: cx + 0.10*r, y: cy - 1.75*r)
                let hat = CGMutablePath()
                hat.move(to: hatTop)
                hat.addLine(to: CGPoint(x: cx - 0.34*r, y: cy - 1.00*r))
                hat.addLine(to: CGPoint(x: cx + 0.42*r, y: cy - 1.08*r))
                hat.closeSubpath()
                g.addPath(hat); g.setFillColor(rgb(0xB39BC8).cgColor); g.fillPath()
                g.setFillColor(haloColor.cgColor)
                g.fillEllipse(in: CGRect(x: hatTop.x - 0.09*r, y: hatTop.y - 0.09*r, width: 0.18*r, height: 0.18*r))
            }
            for (i, cc) in confetti.enumerated() {
                let ang = CGFloat(i) * (2*CGFloat.pi/CGFloat(confetti.count)) - 0.5
                let px = cx + cos(ang)*1.45*r, py = cy + sin(ang)*1.25*r - 0.2*r
                g.setFillColor(cc.cgColor)
                g.fill(CGRect(x: px - 0.07*r, y: py - 0.05*r, width: 0.14*r, height: 0.10*r))
            }
        }

        if ((state == "healthy" && !blink) || isParty) && !puddle {
            g.setFillColor(blushColor.cgColor)
            g.fillEllipse(in: CGRect(x: cx - eyeDX - 0.30*r, y: cy + 0.16*r, width: 0.30*r, height: 0.16*r))
            g.fillEllipse(in: CGRect(x: cx + eyeDX + 0.00*r, y: cy + 0.16*r, width: 0.30*r, height: 0.16*r))
        }

        g.restoreGState() // end breathing/bob transform
    }
}

/// Renders the pet sprite for a given animation frame. The frame counter lives
/// in the parent (MascotBand) so the pet and its speech bubble share one clock.
struct PetSpriteView: View {
    let style: String
    let state: String
    let size: CGFloat
    let frame: Int

    var body: some View {
        Image(nsImage: PixelPet.sprite(style: style, state: state, grid: Int(size), frame: frame))
            .resizable()
            .interpolation(.none)
            .frame(width: size, height: size)
    }
}
