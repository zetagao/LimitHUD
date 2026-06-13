import SwiftUI
import AppKit

/// Neutral text colors for the card (custom or theme-derived).
struct CardPalette {
    let ink: Color
    let dim: Color
    let muted: Color
    let muted2: Color
}

/// Floating quota card. Scalable, appearance-adaptive, custom background & text color.
struct HUDView: View {
    @ObservedObject var store: QuotaStore
    @ObservedObject private var settings = Settings.shared
    @Environment(\.colorScheme) private var systemScheme
    var onClose: () -> Void = {}
    var onSettings: () -> Void = {}
    var onPin: () -> Void = {}

    @State private var now = Date()
    /// Stable pet mood shown on the card. A transient no-data blip during refresh
    /// keeps the last real mood (no flicker), but a genuinely-empty quota still
    /// shows the gray "dead" animation.
    @State private var petState = "healthy"
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var s: CGFloat { settings.cardScale }
    private var scheme: ColorScheme {
        settings.cardBgCustom ? (settings.cardBgIsLight ? .light : .dark) : systemScheme
    }
    private var p: CardPalette {
        if settings.cardFgCustom {
            let c = settings.cardFgColor
            return CardPalette(ink: c, dim: c.opacity(0.85), muted: c.opacity(0.6), muted2: c.opacity(0.42))
        }
        return CardPalette(ink: Theme.ink, dim: Theme.inkDim, muted: Theme.muted, muted2: Theme.muted2)
    }
    private var barColor: Color? { settings.cardBarCustom ? settings.cardBarColor : nil }

    /// Tightest visible window across all providers — the real constraint.
    private var bottleneck: (provider: String, window: QuotaWindow)? {
        var best: (String, QuotaWindow)?
        for provider in store.providers where provider.error == nil {
            for w in provider.windows
            where !settings.hiddenWindows.contains("\(provider.name)/\(w.label)") {
                if best == nil || w.remaining < best!.1.remaining { best = (provider.name, w) }
            }
        }
        return best.map { (provider: $0.0, window: $0.1) }
    }

    private var mascotState: String {
        PixelPet.state(remaining: bottleneck?.window.remaining, lastRefill: store.lastRefill, now: now)
    }

    /// What the pet "says" — per-character voice in the title, factual subtitle.
    /// Lines rotate each refresh so the card feels alive.
    private var mascotLine: (title: String, subtitle: String, accent: Color) {
        // Stable between refreshes, changes when new data lands.
        let seed = Int((store.lastUpdated ?? .distantPast).timeIntervalSince1970 / 60)
        let title = PetVoice.title(style: settings.petStyle, state: petState, seed: seed)
        guard let b = bottleneck else {
            return (title, "fetching quota", p.muted)
        }
        let prov = b.provider
        let color = barColor ?? Theme.quotaColor(remaining: b.window.remaining)
        switch petState {
        case "party":   return (title, "quota refilled", Theme.success)
        case "healthy": return (title, "\(prov) · lots left", color)
        case "caution": return (title, "\(prov) · easing down", color)
        case "danger":  return (title, "\(prov) · nearly dry", color)
        case "dead":    return (title, b.window.resetCountdown.map { "back in \($0)" } ?? "resets soon", color)
        default:        return (prov, "—", p.muted)
        }
    }

    /// Update the shown mood, ignoring only the transient no-data blip during a
    /// refresh (which would otherwise flicker gray). A genuinely-empty quota
    /// ("dead") is real and keeps its gray animation.
    private func updatePetState(_ raw: String) {
        guard raw != "sleep" else { return }
        petState = raw
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11 * s) {
            header
            MascotBand(style: settings.petStyle, state: petState,
                       title: mascotLine.title, subtitle: mascotLine.subtitle,
                       accent: mascotLine.accent, s: s, p: p)
            if let b = bottleneck {
                BottleneckHero(provider: b.provider, window: b.window, s: s, p: p,
                               bar: barColor, refillAt: store.lastRefill)
            }
            VStack(alignment: .leading, spacing: 11 * s) {
                ForEach(store.providers) { provider in
                    let visible = provider.windows.filter {
                        !settings.hiddenWindows.contains("\(provider.name)/\($0.label)")
                    }
                    if provider.error != nil || !visible.isEmpty {
                        ProviderSection(provider: provider, windows: visible, s: s, p: p, bar: barColor)
                    }
                }
            }
            Rectangle().fill(Theme.border).frame(height: 1)
            footer
        }
        .padding(12 * s)
        .frame(width: 206 * s, alignment: .leading)
        .background {
            if settings.cardBgCustom {
                RoundedRectangle(cornerRadius: 14 * s, style: .continuous)
                    .fill(settings.cardBgColor)
            } else {
                // Premium deep-dark by default — a dense Framea-dark tint with
                // just a hint of frosted glass underneath (stays dark on any wallpaper).
                FrostedBackground()
                    .overlay(Theme.surface.opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 14 * s, style: .continuous))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 14 * s, style: .continuous)
                .strokeBorder(Theme.border2, lineWidth: 1)
        )
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: 14 * s, style: .continuous)
                .fill(LinearGradient(colors: [Color.white.opacity(0.05), .clear],
                                     startPoint: .top, endPoint: .center))
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
        }
        .environment(\.colorScheme, scheme)
        .opacity(settings.opacity)
        .onReceive(ticker) { now = $0 }
        .onAppear { updatePetState(mascotState) }
        .onChange(of: mascotState) { updatePetState($0) }
    }

    private var header: some View {
        HStack(spacing: 7 * s) {
            Text("AI QUOTA").monoLabel(size: 9.5 * s, tracking: 1.6 * s, color: p.muted)
            Spacer(minLength: 6 * s)
            iconButton("arrow.clockwise", spinning: store.isRefreshing) { store.refresh() }
            iconButton("gearshape") { onSettings() }
            iconButton(settings.cardPinned ? "pin.fill" : "pin",
                       tint: settings.cardPinned ? Theme.accent : nil) { onPin() }
            iconButton("xmark") { onClose() }
        }
    }

    private func iconButton(_ system: String, spinning: Bool = false, tint: Color? = nil, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 10 * s, weight: .medium))
                .foregroundColor(tint ?? p.muted)
                .frame(width: 19 * s, height: 19 * s)
                .background(Color.white.opacity(0.001))
                .rotationEffect(.degrees(spinning ? 360 : 0))
                .animation(spinning ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: spinning)
        }
        .buttonStyle(IconButtonStyle())
    }

    private var footer: some View {
        HStack(spacing: 6 * s) {
            if let last = store.lastUpdated {
                Text("SYNCED \(timeString(last))")
                    .font(.system(size: 9 * s, weight: .bold, design: .monospaced))
                    .tracking(0.8 * s)
                    .foregroundColor(p.muted2)
            }
            Spacer(minLength: 6 * s)
            Text(settings.hotKeyDisplay)
                .font(.system(size: 9.5 * s, weight: .medium, design: .monospaced))
                .foregroundColor(p.muted2)
                .padding(.horizontal, 4.5 * s)
                .padding(.vertical, 1 * s)
                .overlay(RoundedRectangle(cornerRadius: 4 * s).strokeBorder(Theme.border2, lineWidth: 1))
        }
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}

/// Big animated pet + a speech bubble it physically plays with. A shared frame
/// clock drives both, so the pet's bump and the bubble's wobble stay in sync.
private struct MascotBand: View {
    let style: String
    let state: String
    let title: String
    let subtitle: String
    let accent: Color
    let s: CGFloat
    let p: CardPalette

    var body: some View {
        // Wall-clock driven so the frame counter can never get stuck on one move.
        TimelineView(.periodic(from: .now, by: 0.05)) { context in
            let frame = Int(context.date.timeIntervalSinceReferenceDate * 20)
            let c = Choreo.compute(style: style, state: state, frame: frame, s: s)
            HStack(spacing: 4 * s) {
                PetSpriteView(style: style, state: state, size: 50 * s, frame: frame)
                    .overlay(alignment: .trailing) {
                        if c.pawT > 0.01 { // cat's swatting paw pokes toward the bubble
                            PawShape()
                                .fill(accent)
                                .frame(width: 12 * s, height: 9 * s)
                                .offset(x: c.pawT * 13 * s, y: -1 * s)
                                .opacity(Double(min(1, c.pawT * 1.6)))
                        }
                    }
                    .overlay {
                        if !c.emote.isEmpty && c.emoteOpacity > 0.02 {
                            Text(c.emote)
                                .font(.system(size: 13 * s, weight: .bold))
                                .foregroundColor(accent)
                                .scaleEffect(c.emoteScale)
                                .opacity(c.emoteOpacity)
                                .offset(x: c.emoteDX, y: c.emoteDY)
                                .allowsHitTesting(false)
                        }
                    }
                    .scaleEffect(x: c.petSX, y: c.petSY, anchor: c.petAnchor)
                    .rotationEffect(.degrees(c.petRot), anchor: c.petAnchor)
                    .offset(x: c.petDX, y: c.petDY)
                    .opacity(c.petOpacity)
                    .zIndex(1)
                    .id(style) // rebuild on character switch so no stale sprite lingers
                bubble(c)
                    .scaleEffect(x: c.bubSX, y: c.bubSY, anchor: .leading)
                    .rotationEffect(.degrees(c.bubRot), anchor: .leading)
                    .offset(x: c.bubDX, y: c.bubDY)
                    .opacity(c.bubOpacity)
                Spacer(minLength: 0)
            }
        }
    }

    private func bubble(_ c: Choreo) -> some View {
        VStack(alignment: .leading, spacing: 2 * s) {
            Text(title)
                .font(.system(size: 12 * s, weight: .semibold))
                .foregroundColor(accent)
                .lineLimit(1).minimumScaleFactor(0.8)
            Text(subtitle)
                .font(.system(size: 9.5 * s, weight: .medium, design: .monospaced))
                .foregroundColor(p.muted)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .scaleEffect(c.textScale)            // text jolts when the bubble is bumped
        .offset(x: c.textDX)
        .padding(.leading, 9 * s)
        .padding(.trailing, 11 * s)
        .padding(.vertical, 7 * s)
        .background(SpeechBubble(radius: 9 * s, tail: 5 * s).fill(Color.primary.opacity(0.07)))
        .overlay(SpeechBubble(radius: 9 * s, tail: 5 * s).stroke(Color.primary.opacity(0.18), lineWidth: 1))
        .opacity(1 - 0.92 * Double(c.shatter)) // dissolves as it shatters…
        .overlay { if c.shatter > 0.02 { ShatterView(progress: c.shatter, style: c.shatterStyle, s: s) } }
    }
}

/// The bubble breaking apart on a smash, then flying back together. Several
/// styles so no two smashes look the same: radial shards, gravity drop, pixels.
private struct ShatterView: View {
    let progress: CGFloat
    let style: Int
    let s: CGFloat

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                switch style {
                case 1: dropShards(w, h)
                case 2: pixelCloud(w, h)
                case 3: meltDrips(w, h)
                default: radialShards(w, h)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func shard(_ w: CGFloat, _ h: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 3 * s, style: .continuous)
            .fill(Color.primary.opacity(0.12))
            .overlay(RoundedRectangle(cornerRadius: 3 * s, style: .continuous)
                .stroke(Theme.border2, lineWidth: 1))
            .frame(width: w, height: h)
    }

    private func radialShards(_ w: CGFloat, _ h: CGFloat) -> some View {
        ForEach(0..<6, id: \.self) { i in
            let ang = Double(i) / 6 * 2 * .pi + 0.4
            let dist = progress * 24 * s
            shard(w * 0.34, h * 0.40)
                .rotationEffect(.degrees(Double(progress) * (i % 2 == 0 ? 38 : -30)))
                .position(x: w / 2 + CGFloat(cos(ang)) * dist, y: h / 2 + CGFloat(sin(ang)) * dist)
                .opacity(Double(min(1, progress * 2.4)))
        }
    }

    private func dropShards(_ w: CGFloat, _ h: CGFloat) -> some View {
        ForEach(0..<5, id: \.self) { i in
            let spread = (CGFloat(i) - 2) * w * 0.17
            let fall = progress * progress * 30 * s
            shard(w * 0.30, h * 0.46)
                .rotationEffect(.degrees(Double(progress) * (i % 2 == 0 ? 26 : -22)))
                .position(x: w / 2 + spread * progress, y: h / 2 + fall)
                .opacity(Double(min(1, progress * 2.4)))
        }
    }

    private func meltDrips(_ w: CGFloat, _ h: CGFloat) -> some View {
        ForEach(0..<5, id: \.self) { i in
            let bx = w * (CGFloat(i) + 0.5) / 5
            let drip = progress * (16 + CGFloat((i * 7) % 13)) * s // uneven drips
            Capsule()
                .fill(Color.primary.opacity(0.12))
                .frame(width: w / 5 * 0.74, height: h * 0.46 + drip)
                .position(x: bx, y: h * 0.42 + (h * 0.46 + drip) / 2 - h * 0.23)
                .opacity(Double(min(1, progress * 2.2)))
        }
    }

    private func pixelCloud(_ w: CGFloat, _ h: CGFloat) -> some View {
        let cols = 6, rows = 3
        return ForEach(0..<(cols * rows), id: \.self) { idx in
            let cx = idx % cols, ry = idx / cols
            let baseX = w * (CGFloat(cx) + 0.5) / CGFloat(cols)
            let baseY = h * (CGFloat(ry) + 0.5) / CGFloat(rows)
            let seed = Double(idx) * 2.3994
            let vx = CGFloat(cos(seed)) * 24 * s, vy = CGFloat(sin(seed * 1.7)) * 20 * s
            RoundedRectangle(cornerRadius: 1.5 * s, style: .continuous)
                .fill(Color.primary.opacity(0.12))
                .frame(width: w / CGFloat(cols) * 0.78, height: h / CGFloat(rows) * 0.78)
                .position(x: baseX + vx * progress, y: baseY + vy * progress)
                .opacity(Double(min(1, progress * 2.0)))
        }
    }
}

/// All the per-frame transforms for one interaction beat (pet bump + bubble
/// reaction). Each character bumps the bubble its own way ~once per cycle.
private struct Choreo {
    var petDX: CGFloat = 0, petDY: CGFloat = 0, petRot: Double = 0
    var petSX: CGFloat = 1, petSY: CGFloat = 1, petOpacity: Double = 1
    var pawT: CGFloat = 0
    var bubDX: CGFloat = 0, bubDY: CGFloat = 0, bubSX: CGFloat = 1, bubSY: CGFloat = 1
    var bubRot: Double = 0, bubOpacity: Double = 1
    // A little emote that makes each action instantly recognizable.
    var emote: String = ""
    var emoteDX: CGFloat = 0, emoteDY: CGFloat = 0
    var emoteScale: CGFloat = 1, emoteOpacity: Double = 0
    var petAnchor: UnitPoint = .bottom // .center for a tumble
    var textScale: CGFloat = 1, textDX: CGFloat = 0 // text bounces when bumped
    var shatter: CGFloat = 0 // 0 whole … 1 fully scattered into shards
    var shatterStyle: Int = 0 // which break effect (shards / drop / pixels)

    /// One thing the pet might do in a cycle. Some touch the bubble, some don't.
    private enum Move {
        case contact, smash, rest
        case wag, zoomies, rollOver, sniff      // dog: energetic, grounded
        case ignore, knock, stretch, loaf       // cat: aloof, slow, lateral
        case drift, swirl, vanish               // ghost: floaty, opacity-based
        case jiggle, springHop, plop            // mochi: squishy, scale-based
        // state-signature moves
        case alert      // dog danger: frantic warning bumps
        case puff       // cat danger: arch up and recoil
        case flicker    // ghost danger: erratic flicker
        case panic      // mochi danger: violent shaking
        case peek       // caution: a wary glance around
        case doze       // sleep: barely stirs, drifting z's
    }

    /// Each character's repertoire varies by mood — different actions, not just
    /// pace. Rotated per cycle; `.rest` cycles leave a natural pause.
    private static func repertoire(_ style: String, _ state: String) -> [Move] {
        switch (style, state) {
        // 🐶 dog
        case ("inu", "caution"): return [.contact, .sniff, .peek, .wag, .rest, .rest]
        case ("inu", "danger"):  return [.alert, .alert, .contact, .peek, .smash]
        case ("inu", "party"):   return [.zoomies, .rollOver, .wag, .smash, .contact, .zoomies]
        case ("inu", "sleep"):   return [.doze, .rest]
        case ("inu", _):         return [.contact, .wag, .zoomies, .rollOver, .sniff, .smash, .rest]
        // 🐱 cat
        case ("neko", "caution"): return [.ignore, .peek, .stretch, .knock, .rest, .rest]
        case ("neko", "danger"):  return [.puff, .puff, .contact, .ignore, .smash]
        case ("neko", "party"):   return [.knock, .zoomies, .contact, .smash, .knock]
        case ("neko", "sleep"):   return [.loaf, .doze, .rest]
        case ("neko", _):         return [.contact, .ignore, .knock, .stretch, .loaf, .smash, .rest]
        // 👻 ghost
        case ("boo", "caution"): return [.drift, .peek, .vanish, .rest, .rest]
        case ("boo", "danger"):  return [.flicker, .flicker, .contact, .vanish, .smash]
        case ("boo", "party"):   return [.swirl, .vanish, .contact, .smash, .swirl]
        case ("boo", "sleep"):   return [.doze, .drift, .rest]
        case ("boo", _):         return [.contact, .drift, .swirl, .vanish, .smash, .rest]
        // 🍡 mochi
        case (_, "caution"): return [.jiggle, .peek, .plop, .rest, .rest]
        case (_, "danger"):  return [.panic, .panic, .contact, .smash]
        case (_, "party"):   return [.springHop, .plop, .jiggle, .smash, .springHop]
        case (_, "sleep"):   return [.doze, .rest]
        default:             return [.contact, .jiggle, .springHop, .plop, .smash, .rest]
        }
    }

    private static func length(_ m: Move) -> Int {
        switch m {
        case .contact:   return 24
        case .smash:     return 46
        case .rest:      return 0
        case .wag:       return 32
        case .zoomies:   return 32
        case .rollOver:  return 38
        case .sniff:     return 30
        case .ignore:    return 34
        case .knock:     return 44
        case .stretch:   return 34
        case .loaf:      return 32
        case .drift:     return 40
        case .swirl:     return 40
        case .vanish:    return 36
        case .jiggle:    return 34
        case .springHop: return 30
        case .plop:      return 34
        case .alert:     return 38
        case .puff:      return 32
        case .flicker:   return 34
        case .panic:     return 32
        case .peek:      return 30
        case .doze:      return 44
        }
    }

    private static func bell(_ x: CGFloat, _ ctr: CGFloat, _ w: CGFloat) -> CGFloat {
        let z = (x - ctr) / w; return exp(-z * z)
    }
    /// Damped spring the bubble rides after a contact at `hitLP`.
    private static func spring(_ lp: CGFloat, _ hitLP: CGFloat, _ win: Int) -> CGFloat {
        let t = (lp - hitLP) * CGFloat(win)
        return t < 0 ? 0 : exp(-t / 7) * CGFloat(cos(Double(t) * 0.7))
    }

    static func compute(style: String, state: String, frame: Int, s: CGFloat) -> Choreo {
        var c = Choreo()
        if state == "dead" { return c } // flatlined — bubble holds still too

        // The bubble is always quietly alive: a slow breath on its own clock,
        // slightly out of phase with the pet so they feel like two creatures.
        let ab = 2 * Double.pi * Double(((frame % 90) + 90) % 90) / 90
        c.bubSX += 0.016 * CGFloat(sin(ab))
        c.bubSY += 0.013 * CGFloat(sin(ab + 1.0))
        c.bubDY += 1.4 * s * CGFloat(sin(ab * 0.5))

        // Mood sets the pace: danger/party are quick & frantic, caution hangs
        // back, sleep is glacial.
        let period: Int
        switch state {
        case "danger": period = 52
        case "party":  period = 54
        case "caution": period = 88
        case "sleep":  period = 120
        default:       period = 72
        }
        let cycle = max(0, frame) / period
        let f = ((frame % period) + period) % period
        let list = repertoire(style, state)
        let move = list[cycle % list.count]

        // A constant nervous tremble whenever the quota is critical.
        if state == "danger" {
            c.petDX += 1.0 * s * CGFloat(sin(Double(frame) * 1.9))
            c.petDY += 0.7 * s * CGFloat(sin(Double(frame) * 2.3))
        }
        if move == .rest { return c }

        // Place the move with a per-cycle jitter so it never lands on the exact
        // same beat twice in a row.
        let win = length(move)
        let jitter = (cycle * 13) % 10
        let wStart = period - win - 3 - jitter
        guard f >= wStart, f < wStart + win else { return c }
        let lp = CGFloat(f - wStart) / CGFloat(win)
        let k: CGFloat = state == "party" ? 1.35 : (state == "danger" ? 1.2 : (state == "caution" ? 0.8 : 1.0))

        let env = CGFloat(sin(Double(lp) * .pi)) // ramp-in/out for held gestures
        switch move {
        case .contact:
            let windup = bell(lp, 0.18, 0.11), lunge = bell(lp, 0.42, 0.10)
            let H = spring(lp, 0.42, win)
            applyContact(&c, style: style, forward: lunge - 0.45 * windup, press: lunge, hit: H, k: k, s: s)
            burst(&c, "✦", after: lp, from: 0.42, s: s)
            bumpText(&c, H, s: s)

        // ───── 🐶 dog: bouncy, waggy, grounded ─────
        case .wag: // fast tail-wag whole-body shimmy
            let osc = CGFloat(sin(Double(lp) * .pi * 7))
            c.petRot = Double(17 * env * osc)
            c.petDX = 4 * s * env * osc
            c.bubRot += Double(5 * env * CGFloat(sin(Double(lp) * .pi * 7 + 0.6)))
            float(&c, "♪", lp: lp, s: s, dx: 16)
        case .zoomies: // three quick excited bounces
            let arch = CGFloat(abs(sin(Double(lp) * .pi * 3)))
            c.petDY = -12 * s * arch * k
            c.petSY = 1 + 0.09 * (1 - arch); c.petSX = 1 - 0.07 * (1 - arch)
            c.bubDY += -3 * s * CGFloat(abs(sin((Double(lp) - 0.08) * .pi * 3)))
            let e = bell(lp, 0.2, 0.12)
            c.emote = "✧"; c.emoteOpacity = Double(e); c.emoteScale = 0.7 + 0.5 * e
            c.emoteDX = 2 * s; c.emoteDY = -30 * s
        case .rollOver: // a full belly roll
            let spin = lp * lp * (3 - 2 * lp)
            c.petRot = Double(360 * spin); c.petAnchor = .center
            let arch = CGFloat(sin(Double(lp) * .pi))
            c.petDY = -6 * s * arch; c.petDX = 6 * s * arch
            let e = bell(lp, 0.5, 0.24)
            c.emote = "↻"; c.emoteOpacity = Double(e) * 0.8; c.emoteScale = 0.9 + 0.3 * e; c.emoteDY = -28 * s
        case .sniff: // leans in close and sniffs the bubble
            let lean = bell(lp, 0.45, 0.18)
            applyContact(&c, style: "inu", forward: lean, press: 0.4 * lean, hit: 0.4 * spring(lp, 0.5, win), k: k, s: s)
            float(&c, "♡", lp: lp, s: s, dx: 22)

        // ───── 🐱 cat: aloof, slow, minimal ─────
        case .ignore: // slowly turns its back, gives a tail flick
            c.petRot = Double(-18 * env)
            c.petDX = -3 * s * env
        case .knock: // bats the bubble and slides it away — the classic cat move
            let push = bell(lp, 0.32, 0.10)
            c.pawT = max(0, push * 1.1)
            c.petDX = push * 4 * s
            if lp >= 0.32 { // shoved right, then slowly creeps back
                let slide = 1 - (lp - 0.32) / 0.68
                c.bubDX += 13 * s * CGFloat(max(0, slide))
                c.bubRot += Double(max(0, slide)) * 3
            }
        case .stretch: // a long, languid arch
            c.petSY = 1 + 0.18 * env; c.petSX = 1 - 0.10 * env
            c.petDY = -3 * s * env
        case .loaf: // settles into a loaf, half-asleep
            c.petSY = 1 - 0.10 * env; c.petSX = 1 + 0.09 * env
            c.emote = "z"; c.emoteOpacity = Double(env) * 0.7; c.emoteScale = 0.85
            c.emoteDX = 16 * s; c.emoteDY = -22 * s

        // ───── 👻 ghost: floats, fades, swirls ─────
        case .drift: // floats up, sways, slightly fades
            c.petDY = -10 * s * env
            c.petDX = 3 * s * CGFloat(sin(Double(lp) * .pi * 2))
            c.petOpacity = 1 - 0.18 * Double(env)
        case .swirl: // a slow ethereal spin with a flicker
            c.petRot = Double(360 * lp); c.petAnchor = .center
            c.petOpacity = 0.65 + 0.35 * Double(abs(sin(Double(lp) * .pi * 2)))
            let e = bell(lp, 0.5, 0.3)
            c.emote = "↻"; c.emoteOpacity = Double(e) * 0.6; c.emoteScale = 0.9; c.emoteDY = -27 * s
        case .vanish: // fades right out, then pops back — "boo!"
            let dip = CGFloat(sin(Double(lp) * .pi))
            c.petOpacity = 1 - 0.92 * Double(dip)
            if lp > 0.6 {
                let e = bell(lp, 0.72, 0.08)
                c.emote = "!"; c.emoteOpacity = Double(e); c.emoteScale = 0.8 + 0.5 * e
                c.emoteDX = 4 * s; c.emoteDY = -24 * s
            }

        // ───── 🍡 mochi: pure squish & bounce ─────
        case .jiggle: // wobbles like jelly in place
            let w = CGFloat(sin(Double(lp) * .pi * 6))
            c.petSX = 1 + 0.13 * env * w; c.petSY = 1 - 0.13 * env * w
            float(&c, "~", lp: lp, s: s, dx: 14)
        case .springHop: // anticipation squash → stretch → land
            let arch = CGFloat(abs(sin(Double(lp) * .pi * 2)))
            c.petDY = -10 * s * arch * k
            c.petSY = 1 + 0.13 * arch - 0.11 * (1 - arch)
            c.petSX = 1 - 0.11 * arch + 0.11 * (1 - arch)
        case .plop: // stretches tall, then plops flat and rebounds
            let up = bell(lp, 0.32, 0.12), down = bell(lp, 0.56, 0.09)
            c.petSY = 1 + 0.26 * up - 0.22 * down
            c.petSX = 1 - 0.16 * up + 0.22 * down
            c.petDY = -6 * s * up + 2 * s * down

        // ───── 🔴 danger signatures (per character) ─────
        case .alert: // dog: frantic warning bumps + "!"
            let p1 = bell(lp, 0.22, 0.05), p2 = bell(lp, 0.46, 0.05), p3 = bell(lp, 0.70, 0.05)
            let H = spring(lp, 0.22, win) + spring(lp, 0.46, win) + spring(lp, 0.70, win)
            applyContact(&c, style: "inu", forward: p1 + p2 + p3, press: p1 + p2 + p3, hit: H, k: k, s: s)
            bumpText(&c, H, s: s)
            let e = bell(lp, 0.5, 0.3)
            c.emote = "!"; c.emoteOpacity = Double(e); c.emoteScale = 0.85 + 0.4 * e
            c.emoteDX = 4 * s; c.emoteDY = -26 * s
        case .puff: // cat: arches up, bristles, recoils
            c.petSY = 1 + 0.22 * env; c.petSX = 1 - 0.05 * env
            c.petDX = -5 * s * env
            c.petRot = Double(-6 * CGFloat(sin(Double(lp) * .pi * 9))) * Double(env)
            let e = bell(lp, 0.5, 0.3)
            c.emote = "!"; c.emoteOpacity = Double(e); c.emoteScale = 0.85; c.emoteDX = -3 * s; c.emoteDY = -28 * s
        case .flicker: // ghost: erratic flicker + jitter
            c.petOpacity = 0.28 + 0.72 * Double(abs(sin(Double(lp) * .pi * 9)))
            c.petDX = 4 * s * CGFloat(sin(Double(lp) * .pi * 11))
            c.petDY = -3 * s * CGFloat(sin(Double(lp) * .pi * 7))
            let e = bell(lp, 0.5, 0.3)
            c.emote = "!"; c.emoteOpacity = Double(e) * 0.9; c.emoteScale = 0.85; c.emoteDY = -26 * s
        case .panic: // mochi: violent fast wobble
            let w = CGFloat(sin(Double(lp) * .pi * 9))
            c.petSX = 1 + 0.18 * env * w; c.petSY = 1 - 0.18 * env * w
            c.petDX = 3 * s * CGFloat(sin(Double(lp) * .pi * 11))
            let e = bell(lp, 0.5, 0.3)
            c.emote = "!"; c.emoteOpacity = Double(e); c.emoteScale = 0.85; c.emoteDY = -27 * s

        // ───── 🟡 caution / 😴 sleep shared ─────
        case .peek: // a slow wary glance around
            c.petRot = Double(-11 * env)
            c.petDX = -2 * s * env
            c.emote = "?"; c.emoteOpacity = Double(env) * 0.75; c.emoteScale = 0.85
            c.emoteDX = -2 * s; c.emoteDY = -24 * s
        case .doze: // barely stirs; drifting z's
            c.petSY = 1 - 0.04 * env; c.petSX = 1 + 0.03 * env
            c.emote = "z"; c.emoteOpacity = Double(env) * 0.6; c.emoteScale = 0.8
            c.emoteDX = 15 * s; c.emoteDY = -20 * s - 6 * s * lp

        case .smash: // each character's signature finisher (in-character attack)
            let windup = bell(lp, 0.20, 0.10), lunge = bell(lp, 0.44, 0.06)
            let H = spring(lp, 0.44, win)
            switch style {
            case "neko": c.pawT = max(0, lunge * 1.2); c.petDX = (lunge - 0.3 * windup) * 5 * s
            case "boo":  c.petDX = (lunge - 0.3 * windup) * 16 * s; c.petOpacity = 1 - 0.5 * Double(lunge)
            case "mochi": c.petDX = (lunge - 0.4 * windup) * 12 * s; c.petSX = 1 - 0.14 * lunge; c.petSY = 1 + 0.10 * lunge
            default:     c.petDX = (lunge - 0.5 * windup) * 16 * s * k; c.petDY = lunge * 3 * s; c.petRot = Double(lunge - 0.5 * windup) * 7
            }
            bumpText(&c, H, s: s)
            burst(&c, "✦", after: lp, from: 0.44, s: s)
            let prog = lp > 0.44 ? CGFloat(sin(Double(min(1, (lp - 0.44) / 0.5)) * .pi)) : 0
            // Each character owns two signature break effects; alternate them.
            let pair: (Int, Int)
            switch style {
            case "inu":  pair = (0, 4) // radial shatter / knocked flying
            case "neko": pair = (1, 6) // gravity drop / rolled up
            case "boo":  pair = (2, 5) // pixel dissolve / melt
            default:     pair = (3, 7) // mochi: crushed flat / spring-stretch
            }
            let eff = ((cycle / list.count) % 2 == 0) ? pair.0 : pair.1
            applyBreak(&c, eff, prog: prog, H: H, lp: lp, win: win, s: s)
        case .rest:
            break
        }
        return c
    }

    /// One of the eight bubble-break effects, by id.
    private static func applyBreak(_ c: inout Choreo, _ eff: Int,
                                   prog: CGFloat, H: CGFloat, lp: CGFloat, win: Int, s: CGFloat) {
        let shake = CGFloat(sin(Double(lp) * .pi * 18))
        switch eff {
        case 1: c.shatterStyle = 1; c.shatter = prog; c.bubRot += Double(H) * 5 * shake
        case 2: c.shatterStyle = 2; c.shatter = prog
        case 3: c.bubSY += -0.82 * prog; c.bubSX += 0.22 * prog; c.bubRot += Double(H) * 6 * shake
        case 4: c.bubDX += 30 * s * prog; c.bubDY += -8 * s * prog
                c.bubRot += 330 * Double(prog); c.bubSX += -0.45 * prog; c.bubSY += -0.45 * prog
        case 5: c.shatterStyle = 3; c.shatter = prog; c.bubDY += 3 * s * prog
        case 6: c.bubSX += -1.0 * prog; c.bubRot += 7 * Double(prog)
        case 7: let t2 = (lp - 0.44) * CGFloat(win)
                let ss = t2 < 0 ? 0 : exp(-t2 / 13) * CGFloat(cos(Double(t2) * 1.25))
                c.bubSX += 0.55 * ss; c.bubSY += -0.38 * ss
        default: c.shatterStyle = 0; c.shatter = prog; c.bubDX += 7 * s * H
                 c.bubRot += Double(H) * 9 * CGFloat(sin(Double(lp) * .pi * 20)); c.bubSX += -0.10 * H
        }
    }

    /// Jolt the bubble text when the pet bumps it.
    private static func bumpText(_ c: inout Choreo, _ H: CGFloat, s: CGFloat) {
        c.textScale = 1 + 0.11 * H
        c.textDX = 2.5 * s * H
    }

    /// A star that bursts out from the contact point and fades.
    private static func burst(_ c: inout Choreo, _ glyph: String, after lp: CGFloat, from: CGFloat, s: CGFloat) {
        let t = (lp - from) / 0.32
        guard t > 0, t < 1 else { return }
        c.emote = glyph
        c.emoteScale = 0.6 + 1.3 * t
        c.emoteOpacity = Double(1 - t)
        c.emoteDX = 25 * s
        c.emoteDY = -13 * s - 9 * s * t
    }

    /// A glyph that drifts up off the pet and fades.
    private static func float(_ c: inout Choreo, _ glyph: String, lp: CGFloat, s: CGFloat, dx: CGFloat) {
        let e = CGFloat(sin(Double(lp) * .pi))
        c.emote = glyph
        c.emoteOpacity = Double(e) * 0.9
        c.emoteScale = 0.8 + 0.3 * e
        c.emoteDX = dx * s
        c.emoteDY = -16 * s - 14 * s * lp
    }

    /// The character-specific bump: how each pet hits the bubble and how the
    /// bubble reacts. `forward` is signed lean, `press` ≥ 0, `hit` is the spring.
    private static func applyContact(_ c: inout Choreo, style: String,
                                     forward: CGFloat, press: CGFloat, hit H: CGFloat, k: CGFloat, s: CGFloat) {
        switch style {
        case "inu": // headbutt — dent + bouncy overshoot
            c.petDX = forward * 13 * s * k
            c.petDY = press * 2 * s
            c.petRot = Double(forward) * 5 * Double(k)
            c.bubSX += -0.13 * H * k
            c.bubSY += 0.08 * H * k
            c.bubDX += 5 * s * H * k
        case "neko": // lazy paw swat — bubble swings
            c.petDX = forward * 4 * s
            c.pawT = max(0, press * 1.1)
            c.bubRot += Double(H) * 7 * Double(k)
            c.bubDX += 3 * s * H
        case "boo": // phases in — translucent, bubble ripples
            c.petDX = forward * 17 * s * k
            c.petOpacity = 1 - 0.45 * Double(press)
            c.bubSX += 0.05 * H
            c.bubSY += 0.05 * H
            c.bubOpacity += -0.12 * Double(max(0, press))
        default: // mochi — soft mutual squish
            c.petDX = forward * 12 * s * k
            c.petSX = 1 - 0.12 * press
            c.petSY = 1 + 0.08 * press
            c.bubSX += -0.16 * H * k
            c.bubSY += 0.10 * H * k
        }
    }
}

/// A tiny cat paw (palm + three toes) for the swat gesture.
private struct PawShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let palm = CGRect(x: r.minX, y: r.minY + r.height * 0.30,
                          width: r.width * 0.78, height: r.height * 0.70)
        p.addRoundedRect(in: palm, cornerSize: CGSize(width: r.height * 0.3, height: r.height * 0.3))
        let toe = r.width * 0.26
        for i in 0..<3 {
            let tx = r.minX + r.width * 0.10 + CGFloat(i) * (r.width * 0.28)
            p.addEllipse(in: CGRect(x: tx, y: r.minY, width: toe, height: toe * 1.15))
        }
        return p
    }
}

/// Rounded bubble with a small tail pointing left (toward the pet).
private struct SpeechBubble: Shape {
    var radius: CGFloat
    var tail: CGFloat
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let body = CGRect(x: rect.minX + tail, y: rect.minY, width: rect.width - tail, height: rect.height)
        path.addRoundedRect(in: body, cornerSize: CGSize(width: radius, height: radius))
        let midY = rect.midY
        path.move(to: CGPoint(x: rect.minX, y: midY))
        path.addLine(to: CGPoint(x: rect.minX + tail + 1, y: midY - tail))
        path.addLine(to: CGPoint(x: rect.minX + tail + 1, y: midY + tail))
        path.closeSubpath()
        return path
    }
}

/// Big "what's my real ceiling" block — the tightest window, large % + bar.
private struct BottleneckHero: View {
    let provider: String
    let window: QuotaWindow
    let s: CGFloat
    let p: CardPalette
    let bar: Color?
    let refillAt: Date?

    @State private var glow: Double = 0

    private var color: Color { bar ?? Theme.quotaColor(remaining: window.remaining) }

    /// Burn ETA, but only when running out beats the reset (the real constraint).
    private var eta: TimeInterval? {
        guard let e = UsageHistory.shared.burnETA(
            provider: provider, label: window.label, remaining: window.remaining)
        else { return nil }
        if let reset = window.resetsAt {
            let untilReset = reset.timeIntervalSinceNow
            if untilReset > 0, untilReset <= e { return nil } // reset refills first
        }
        return e
    }

    private var spark: [Double] {
        UsageHistory.shared.recent(provider: provider, label: window.label).map(\.r)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6 * s) {
            HStack(alignment: .firstTextBaseline, spacing: 6 * s) {
                Text("\(provider.uppercased()) · \(window.label)".uppercased())
                    .monoLabel(size: 8.5 * s, tracking: 1.4 * s, color: p.muted2)
                Spacer(minLength: 6 * s)
                if let cd = window.resetCountdown {
                    Text(cd).font(.system(size: 9 * s, design: .monospaced)).foregroundColor(p.muted2)
                }
            }
            HStack(alignment: .bottom, spacing: 8 * s) {
                HStack(alignment: .firstTextBaseline, spacing: 4 * s) {
                    Text("\(Int(window.remaining * 100))")
                        .font(.system(size: 30 * s, weight: .bold, design: .rounded))
                        .foregroundColor(color)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.6, dampingFraction: 0.9),
                                   value: Int(window.remaining * 100))
                    Text("% left")
                        .font(.system(size: 11 * s, weight: .medium, design: .monospaced))
                        .foregroundColor(p.muted)
                }
                Spacer(minLength: 4 * s)
                if spark.count >= 2 {
                    Sparkline(values: spark, color: color)
                        .frame(width: 44 * s, height: 18 * s)
                        .padding(.bottom, 3 * s)
                }
            }
            ProgressBar(value: window.remaining, color: color, s: s * 1.6)
            if let e = eta {
                HStack(spacing: 4 * s) {
                    Image(systemName: "flame.fill").font(.system(size: 8 * s))
                    Text("empty in \(etaString(e)) at this rate")
                        .font(.system(size: 9.5 * s, weight: .medium, design: .monospaced))
                }
                .foregroundColor(color.opacity(0.9))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 9 * s)
        .padding(.horizontal, 11 * s)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10 * s, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10 * s, style: .continuous)
                .strokeBorder(color.opacity(0.22), lineWidth: 1)
        )
        .overlay(
            // Refill celebration: a green ring that flares and fades.
            RoundedRectangle(cornerRadius: 10 * s, style: .continuous)
                .strokeBorder(Theme.success.opacity(0.85 * glow), lineWidth: 2)
                .shadow(color: Theme.success.opacity(0.6 * glow), radius: 9)
                .allowsHitTesting(false)
        )
        .onChange(of: refillAt) { at in
            guard at != nil else { return }
            glow = 1
            withAnimation(.easeOut(duration: 1.8)) { glow = 0 }
        }
    }
}

private struct ProviderSection: View {
    let provider: ProviderQuota
    let windows: [QuotaWindow]
    let s: CGFloat
    let p: CardPalette
    let bar: Color?

    private func hm(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: d)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7 * s) {
            HStack(spacing: 5 * s) {
                Text(provider.name.uppercased())
                    .monoLabel(size: 9 * s, tracking: 1.8 * s, color: p.muted2)
                if provider.stale, let lg = provider.lastGood {
                    Text("· last \(hm(lg))")
                        .font(.system(size: 8 * s, weight: .medium, design: .monospaced))
                        .foregroundColor(Theme.warning.opacity(0.9))
                }
            }
            if let error = provider.error {
                HStack(spacing: 5 * s) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 8.5 * s))
                    Text(error).font(.system(size: 10.5 * s, weight: .medium))
                }
                .foregroundColor(Theme.warning)
            } else {
                ForEach(windows) { window in
                    QuotaRow(window: window, s: s, p: p, bar: bar)
                }
            }
        }
    }
}

private struct QuotaRow: View {
    let window: QuotaWindow
    let s: CGFloat
    let p: CardPalette
    let bar: Color?

    private var color: Color { bar ?? Theme.quotaColor(remaining: window.remaining) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4 * s) {
            HStack(alignment: .firstTextBaseline, spacing: 5 * s) {
                Text(window.label).font(.system(size: 11 * s, weight: .medium)).foregroundColor(p.dim)
                Spacer(minLength: 6 * s)
                (
                    Text("\(Int(window.remaining * 100))%")
                        .font(.system(size: 11 * s, weight: .semibold, design: .monospaced))
                        .foregroundColor(color)
                    +
                    Text(" left")
                        .font(.system(size: 8.5 * s, weight: .medium, design: .monospaced))
                        .foregroundColor(p.muted2)
                )
                .contentTransition(.numericText())
                .animation(.spring(response: 0.6, dampingFraction: 0.9),
                           value: Int(window.remaining * 100))
                if let cd = window.resetCountdown {
                    Text(cd).font(.system(size: 9.5 * s, design: .monospaced)).foregroundColor(p.muted2)
                }
            }
            ProgressBar(value: window.remaining, color: color, s: s)
        }
    }
}

private struct ProgressBar: View {
    let value: Double
    let color: Color
    let s: CGFloat

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.trackBg)
                Capsule().fill(color)
                    .frame(width: max(3, geo.size.width * min(1, max(0, value))))
                    .shadow(color: color.opacity(0.45), radius: 2.5)
                    .animation(.spring(response: 0.7, dampingFraction: 0.85), value: value)
            }
        }
        .frame(height: 4 * s)
    }
}

/// Tiny line chart of recent `remaining` values (oldest → newest).
private struct Sparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: 0, y: geo.size.height))
                    pts.forEach { p.addLine(to: $0) }
                    p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                    p.closeSubpath()
                }
                .fill(LinearGradient(colors: [color.opacity(0.22), .clear],
                                     startPoint: .top, endPoint: .bottom))
                Path { p in
                    guard let first = pts.first else { return }
                    p.move(to: first)
                    pts.dropFirst().forEach { p.addLine(to: $0) }
                }
                .stroke(color.opacity(0.85), style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        let lo = values.min() ?? 0, hi = values.max() ?? 1
        let span = max(hi - lo, 0.001)
        let n = max(values.count - 1, 1)
        return values.indices.map { i in
            CGPoint(x: size.width * CGFloat(i) / CGFloat(n),
                    y: size.height * (1 - CGFloat((values[i] - lo) / span)))
        }
    }
}

/// System blur behind the panel — real frosted glass (the wallpaper bleeds through).
private struct FrostedBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

private struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(RoundedRectangle(cornerRadius: 5)
                .fill(configuration.isPressed ? Theme.hoverFill : Color.clear))
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
