import SwiftUI
import AppKit

extension Notification.Name {
    /// Posted right as the card is ordered front, so the SwiftUI view can replay
    /// its staggered entrance animation each time it opens (the panel is reused).
    static let hudCardWillShow = Notification.Name("hudCardWillShow")
}

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
    var onClose: () -> Void = {}
    var onSettings: () -> Void = {}
    var onPin: () -> Void = {}

    @State private var now = Date()
    /// Stable pet mood shown on the card. A transient no-data blip during refresh
    /// keeps the last real mood (no flicker), but a genuinely-empty quota still
    /// shows the gray "dead" animation.
    @State private var petState = "healthy"
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // Card resize: the value a drag started from (one handle drags at a time).
    @State private var dragBase: Double?
    // Entrance animation: 0 = hidden, 1 = fully revealed. One animated value drives
    // the card materialize + a staggered per-section reveal. Replays on every open.
    @State private var entrance: CGFloat = 0

    private var s: CGFloat { settings.cardScale }
    private var scheme: ColorScheme {
        // Default card is always deep-dark (premium), regardless of system theme.
        // A custom background adapts text to that background's brightness.
        settings.cardBgCustom ? (settings.cardBgIsLight ? .light : .dark) : .dark
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
        for item in visibleProviders where item.provider.error == nil {
            for w in item.windows {
                if best == nil || w.remaining < best!.1.remaining { best = (item.provider.name, w) }
            }
        }
        return best.map { (provider: $0.0, window: $0.1) }
    }

    private var visibleProviders: [(provider: ProviderQuota, windows: [QuotaWindow])] {
        store.providers.map { provider in
            let windows = provider.windows.filter {
                !settings.hiddenWindows.contains("\(provider.name)/\($0.label)")
            }
            return (provider, windows)
        }
    }

    private var hasRenderableProvider: Bool {
        visibleProviders.contains { item in
            item.provider.error != nil || !item.windows.isEmpty
        }
    }

    private var noSourcesEnabled: Bool {
        !settings.monitorClaude && !settings.monitorCodex
    }

    private var hasStaleData: Bool {
        store.providers.contains { $0.stale }
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
            if noSourcesEnabled { return (title, "no sources enabled", p.muted) }
            if store.isRefreshing { return (title, "fetching quota", p.muted) }
            if store.providers.allSatisfy({ $0.error != nil }) { return (title, "check sign-in", Theme.warning) }
            if !hasRenderableProvider { return (title, "all windows hidden", p.muted) }
            return (title, "no quota data", p.muted)
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
            revealed(0) { header }
            if let b = bottleneck {
                revealed(1) {
                    BottleneckHero(provider: b.provider,
                                   window: b.window,
                                   s: s * settings.heroScale,
                                   p: p,
                                   bar: barColor,
                                   refillAt: store.lastRefill)
                }
            }
            revealed(2) { quotaList }
            revealed(3) { Rectangle().fill(Theme.border).frame(height: 1) }
            revealed(3) { petCompanion }
            revealed(4) { footer }
            if !settings.introSeen { revealed(5) { introHint } }
        }
        .padding(12 * s)
        .frame(width: settings.cardWidth * s, alignment: .leading)
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
        // Always-there resize hints — no mode, no button. Drag the right edge to
        // set width; drag the bottom-right corner to scale the whole card.
        .overlay(alignment: .trailing) {
            EdgeHint()
                .overlay(DragSurface(cursor: .resizeLeftRight,
                                     onChanged: { d in apply($settings.cardWidth, 160...460, d, 1 / Double(s), 0) },
                                     onEnded: { _ in dragBase = nil }).frame(width: 26, height: 64))
        }
        .overlay(alignment: .bottomTrailing) {
            CornerHint(s: s)
                .overlay(DragSurface(cursor: .nwseResize,
                                     onChanged: { d in apply($settings.cardScale, 0.7...2.0, d, 0.0035, -0.0035) },
                                     onEnded: { _ in dragBase = nil }).frame(width: 52, height: 52))
        }
        .environment(\.colorScheme, scheme)
        // Card materialize: scale up + un-blur + fade in (calm premium reveal).
        .scaleEffect(0.965 + 0.035 * min(1, entrance), anchor: .center)
        .blur(radius: max(0, (1 - entrance) * 3))
        .opacity(settings.opacity * Double(min(1, entrance * 1.6)))
        .onReceive(NotificationCenter.default.publisher(for: .hudCardWillShow)) { _ in playEntrance() }
        .onAppear { playEntrance() }
        .onReceive(ticker) { now = $0 }
        .onAppear { updatePetState(mascotState) }
        .onChange(of: mascotState) { updatePetState($0) }
    }

    /// A quiet companion in the bottom corner: the cat curled in its nest on the
    /// right, softly "saying" a line of gray monospaced text on the left. It just
    /// lives there and animates with its mood (naps when the quota's gone, perks
    /// up on a refill) — it never roams over the data.
    private var petCompanion: some View {
        TimelineView(.periodic(from: .now, by: 0.06)) { context in
            let frame = Int(context.date.timeIntervalSinceReferenceDate * 20)
            let petSize = min(66 * s * settings.petScale, max(48 * s, (settings.cardWidth - 24) * s * 0.46))
            let line = mascotLine
            HStack(alignment: .center, spacing: 10 * s) {
                VStack(alignment: .leading, spacing: 3 * s) {
                    Text(line.title)
                        .font(.system(size: 11 * s, weight: .medium, design: .monospaced))
                        .foregroundColor(p.muted)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(line.subtitle)
                        .font(.system(size: 9 * s, weight: .medium, design: .monospaced))
                        .foregroundColor(p.muted2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 6 * s)
                // No .id(petStyle): swap the character in place so the old pet
                // doesn't linger/flash while the new pet's images load.
                PetSpriteView(style: settings.petStyle, state: petState, size: petSize, frame: frame)
                    .frame(width: petSize, height: petSize)
                    .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var quotaList: some View {
        VStack(alignment: .leading, spacing: 12 * s * settings.listScale) {
            if hasRenderableProvider {
                ForEach(visibleProviders, id: \.provider.id) { item in
                    if item.provider.error != nil || !item.windows.isEmpty {
                        ProviderSection(provider: item.provider,
                                        windows: item.windows,
                                        s: s * settings.listScale,
                                        p: p,
                                        bar: barColor)
                    }
                }
            } else {
                QuotaEmptyState(title: emptyState.title,
                                subtitle: emptyState.subtitle,
                                s: s,
                                p: p)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: (title: String, subtitle: String) {
        if noSourcesEnabled {
            return ("No sources enabled", "Turn on Claude or Codex in Settings to start monitoring.")
        }
        if store.isRefreshing {
            return ("Fetching quota", "Reading local browser sessions now.")
        }
        return ("No visible windows", "Enable at least one quota window in Card Content.")
    }

    private var header: some View {
        HStack(spacing: 7 * s) {
            Text("AI QUOTA").monoLabel(size: 9.5 * s, tracking: 1.6 * s, color: p.muted)
            Spacer(minLength: 6 * s)
            iconButton("arrow.clockwise", spinning: store.isRefreshing) { store.refresh() }
            iconButton("gearshape") { settings.introSeen = true; onSettings() }
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
            Text(footerStatus.text)
                .font(.system(size: 9 * s, weight: .bold, design: .monospaced))
                .tracking(0.8 * s)
                .foregroundColor(footerStatus.color)
            Spacer(minLength: 6 * s)
            Text(settings.hotKeyDisplay)
                .font(.system(size: 9.5 * s, weight: .medium, design: .monospaced))
                .foregroundColor(p.muted2)
                .padding(.horizontal, 4.5 * s)
                .padding(.vertical, 1 * s)
                .overlay(RoundedRectangle(cornerRadius: 4 * s).strokeBorder(Theme.border2, lineWidth: 1))
        }
    }

    /// First-run nudge: a subtle tappable pill that opens Settings to customize.
    private var introHint: some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) { settings.introSeen = true }
            onSettings()
        } label: {
            HStack(spacing: 6 * s) {
                Image(systemName: "hand.wave.fill").font(.system(size: 9 * s))
                Text("New here? Pick your pet & customize")
                    .font(.system(size: 9.5 * s, weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 4 * s)
                Image(systemName: "gearshape.fill").font(.system(size: 9.5 * s))
            }
            .foregroundColor(Theme.accent)
            .padding(.horizontal, 9 * s)
            .padding(.vertical, 6 * s)
            .frame(maxWidth: .infinity)
            .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8 * s, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8 * s, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.32), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var footerStatus: (text: String, color: Color) {
        if store.isRefreshing { return ("REFRESHING", p.muted2) }
        guard let last = store.lastUpdated else { return ("WAITING", p.muted2) }
        if hasStaleData { return ("STALE \(timeString(last))", Theme.warning.opacity(0.9)) }
        return ("SYNCED \(timeString(last))", p.muted2)
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    // MARK: - Entrance animation

    /// Wraps a section so it slides up + fades in as the `entrance` value crosses
    /// its slot, giving a staggered top-to-bottom reveal.
    @ViewBuilder private func revealed<V: View>(_ i: Int, @ViewBuilder _ content: () -> V) -> some View {
        let r = min(1, max(0, (entrance - CGFloat(i) * 0.1) / 0.5))   // this section's reveal 0…1
        content()
            .opacity(Double(r))
            .offset(y: (1 - r) * 8 * s)
    }

    /// Replay the entrance: snap hidden, then spring the whole card in.
    private func playEntrance() {
        entrance = 0
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) { entrance = 1 }
        }
    }

    // MARK: - Card resize

    /// Apply a knob's cumulative screen-space drag to a setting. `base` is captured
    /// on the first event so the value tracks the pointer exactly (no drift even as
    /// the card relays out underneath). kx/ky are points→value gains (AppKit y-up,
    /// so "down" is negative — corners pass a negative ky to grow on a downward drag).
    private func apply(_ binding: Binding<Double>, _ range: ClosedRange<Double>,
                       _ d: CGSize, _ kx: Double, _ ky: Double) {
        if dragBase == nil { dragBase = binding.wrappedValue }
        let v = (dragBase ?? binding.wrappedValue) + Double(d.width) * kx + Double(d.height) * ky
        binding.wrappedValue = min(range.upperBound, max(range.lowerBound, v))
    }
}

/// The cat's little bed in the corner — a raised cushion rim around a soft hollow,
/// so it reads as a bed rather than a shadow blob.
private struct PetNest: View {
    let s: CGFloat
    var body: some View {
        ZStack {
            Ellipse().fill(
                LinearGradient(colors: [Color.white.opacity(0.12), Color.white.opacity(0.035)],
                               startPoint: .top, endPoint: .bottom))
            Ellipse().strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
            Ellipse().fill(Color.black.opacity(0.28))
                .scaleEffect(x: 0.74, y: 0.5, anchor: .center)
                .offset(y: 1 * s)
                .blur(radius: 1.4 * s)
        }
        .allowsHitTesting(false)
    }
}
