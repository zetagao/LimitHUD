import AppKit

// Shows every pose of every (character, state) from the production renderer.
// swiftc -swift-version 5 -o /tmp/posesheet <this as main.swift> Sources/LimitHUD/PixelPet.swift

func hx(_ h: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((h >> 16) & 0xFF)/255, green: CGFloat((h >> 8) & 0xFF)/255,
            blue: CGFloat(h & 0xFF)/255, alpha: a)
}
let muted = hx(0xF4F4F5, 0.55), muted2 = hx(0xF4F4F5, 0.34), ink = hx(0xF4F4F5)

let states = ["healthy", "caution", "danger", "party", "sleep", "dead"]
let designs = [("MOCHI","mochi"), ("NEKO","neko"), ("BOO","boo"), ("INU","inu")]
let cell: CGFloat = 96, pad: CGFloat = 16
let maxPoses = 4
let blockW = CGFloat(maxPoses) * cell + 30
let colW = blockW, rowH = cell + 34
let W = 120 + CGFloat(states.count) * (blockW + 14)
let H = 90 + CGFloat(designs.count) * rowH
let S: CGFloat = 2

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W*S), pixelsHigh: Int(H*S),
                          bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                          colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let nsctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = nsctx
let ctx = nsctx.cgContext
ctx.scaleBy(x: S, y: S)
ctx.translateBy(x: 0, y: H); ctx.scaleBy(x: 1, y: -1)
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)

func text(_ str: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ color: NSColor, _ w: NSFont.Weight = .regular, mono: Bool = false, kern: CGFloat = 0) {
    let f = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: w) : NSFont.systemFont(ofSize: size, weight: w)
    var a: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: color]
    if kern != 0 { a[.kern] = kern }
    (str as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: a)
}
func blit(_ img: NSImage, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat) {
    img.draw(in: NSRect(x: x, y: y, width: w, height: w), from: .zero, operation: .sourceOver,
             fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.none.rawValue])
}

ctx.setFillColor(hx(0x0E0E10).cgColor)
ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
text("LIMITHUD · PET POSES PER STATE", 40, 30, 16, muted, .bold, mono: true, kern: 2)

MainActor.assumeIsolated {
    for (si, st) in states.enumerated() {
        text(st.uppercased(), 120 + CGFloat(si)*(blockW+14), 64, 12, muted2, .bold, mono: true, kern: 1)
    }
    for (ri, d) in designs.enumerated() {
        let y = 84 + CGFloat(ri)*rowH
        text(d.0, 36, y + cell/2, 14, ink, .bold, mono: true, kern: 1)
        for (si, st) in states.enumerated() {
            let bx = 120 + CGFloat(si)*(blockW+14)
            let n = PixelPet.poseCount(st)
            for poseI in 0..<n {
                blit(PixelPet.sprite(style: d.1, state: st, grid: 40, pose: poseI),
                     bx + CGFloat(poseI)*cell, y, cell)
            }
        }
    }
}

try! FileManager.default.createDirectory(atPath: "design", withIntermediateDirectories: true)
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "design/pet-poses.png"
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
