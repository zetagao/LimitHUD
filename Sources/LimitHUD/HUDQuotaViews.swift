import SwiftUI
import AppKit

/// Big "what's my real ceiling" block: the tightest window, large percent and bar.
struct BottleneckHero: View {
    let provider: String
    let window: QuotaWindow
    let s: CGFloat
    let p: CardPalette
    let bar: Color?
    let refillAt: Date?

    @State private var glow: Double = 0

    private static let fastColor = Color(red: 0.97, green: 0.55, blue: 0.2)  // alarm orange

    private var color: Color { bar ?? Theme.quotaColor(remaining: window.remaining) }

    private var eta: TimeInterval? {
        guard let e = UsageHistory.shared.burnETA(
            provider: provider, label: window.label, remaining: window.remaining)
        else { return nil }
        if let reset = window.resetsAt {
            let untilReset = reset.timeIntervalSinceNow
            if untilReset > 0, untilReset <= e { return nil }
        }
        return e
    }

    private var samples: [UsageHistory.Sample] {
        UsageHistory.shared.recent(provider: provider, label: window.label)
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
                        .lineLimit(1)
                    Text("% left")
                        .font(.system(size: 11 * s, weight: .medium, design: .monospaced))
                        .foregroundColor(p.muted)
                        .lineLimit(1)
                }
                .fixedSize(horizontal: true, vertical: false)   // never wrap "100% left"
                .layoutPriority(1)
                Spacer(minLength: 4 * s)
                if samples.count >= 2 {
                    Sparkline(samples: samples, eta: eta, color: color)
                        .frame(maxWidth: 62 * s, maxHeight: 22 * s)   // yields width to the number
                        .padding(.bottom, 3 * s)
                }
            }
            ProgressBar(value: window.remaining, color: color, s: s * 1.6)
            let pace = UsageHistory.shared.pace(provider: provider, label: window.label)
            let fast = (pace ?? 0) >= 1.6
            if fast || eta != nil {
                HStack(spacing: 4 * s) {
                    Image(systemName: "flame.fill").font(.system(size: 8 * s))
                    Text(fast ? "burning \(paceString(pace!)) your usual pace"
                              : "empty in \(etaString(eta!)) at this rate")
                        .font(.system(size: 9.5 * s, weight: .medium, design: .monospaced))
                        .lineLimit(1)                 // never wrap → box height stays fixed
                        .minimumScaleFactor(0.7)      // shrink to fit instead of wrapping
                }
                .foregroundColor(fast ? Self.fastColor : color.opacity(0.9))
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

struct ProviderSection: View {
    let provider: ProviderQuota
    let windows: [QuotaWindow]
    let s: CGFloat
    let p: CardPalette
    let bar: Color?

    private func hm(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
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
            if provider.stale, let reason = provider.staleReason {
                tappable {
                    HStack(spacing: 5 * s) {
                        Image(systemName: "clock.badge.exclamationmark")
                            .font(.system(size: 8.5 * s))
                        Text("showing saved data - \(reason)")
                            .font(.system(size: 9 * s, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .foregroundColor(Theme.warning.opacity(0.9))
                }
            }
            if let error = provider.error {
                tappable {
                    HStack(spacing: 5 * s) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 8.5 * s))
                        Text(error).font(.system(size: 10.5 * s, weight: .medium))
                        if site != nil {
                            Image(systemName: "arrow.up.forward")
                                .font(.system(size: 7 * s, weight: .bold)).opacity(0.7)
                        }
                    }
                    .foregroundColor(Theme.warning)
                }
            } else {
                ForEach(windows) { window in
                    QuotaRow(window: window, s: s, p: p, bar: bar)
                }
            }
        }
    }

    /// Where to send the user to fix a sign-in / token problem for this provider.
    private var site: (name: String, url: URL)? {
        switch provider.name {
        case "Codex":  return ("chatgpt.com", URL(string: "https://chatgpt.com")!)
        case "Claude": return ("claude.ai",  URL(string: "https://claude.ai")!)
        default:       return nil
        }
    }

    /// Wrap a warning row so clicking it opens the provider's site (to re-sign-in).
    @ViewBuilder private func tappable<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        if let site {
            Button { NSWorkspace.shared.open(site.url) } label: {
                content().contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open \(site.name) to sign in")
            .onHover { $0 ? NSCursor.pointingHand.push() : NSCursor.pop() }
        } else {
            content()
        }
    }
}

struct QuotaEmptyState: View {
    let title: String
    let subtitle: String
    let s: CGFloat
    let p: CardPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 4 * s) {
            HStack(spacing: 6 * s) {
                Image(systemName: "eye.slash")
                    .font(.system(size: 10 * s, weight: .medium))
                Text(title)
                    .font(.system(size: 11 * s, weight: .semibold))
            }
            .foregroundColor(p.muted)
            Text(subtitle)
                .font(.system(size: 9.5 * s, weight: .medium))
                .foregroundColor(p.muted2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 9 * s)
        .padding(.horizontal, 10 * s)
        .background(Theme.trackBg.opacity(0.7), in: RoundedRectangle(cornerRadius: 8 * s, style: .continuous))
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
                Capsule()
                    .fill(Theme.trackBg)
                Capsule()
                    .fill(color)
                    .frame(width: geo.size.width * CGFloat(min(1, max(0, value))))
                    .animation(.spring(response: 0.55, dampingFraction: 0.9), value: value)
            }
        }
        .frame(height: 4 * s)
    }
}

/// Trend of recent `remaining` (0% anchored to the bottom), plus an optional
/// dashed forecast line projected from "now" down to empty at the burn-down ETA.
private struct Sparkline: View {
    let samples: [UsageHistory.Sample]   // oldest → newest
    let eta: TimeInterval?               // seconds to empty; nil → no projection
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let L = layout(geo.size)
            ZStack {
                if let first = L.hist.first, let last = L.hist.last {
                    // area fill under the history line
                    Path { p in
                        p.move(to: CGPoint(x: first.x, y: geo.size.height))
                        L.hist.forEach { p.addLine(to: $0) }
                        p.addLine(to: CGPoint(x: last.x, y: geo.size.height))
                        p.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [color.opacity(0.20), .clear],
                                         startPoint: .top, endPoint: .bottom))
                    // history line
                    Path { p in p.move(to: first); L.hist.dropFirst().forEach { p.addLine(to: $0) } }
                        .stroke(color.opacity(0.9),
                                style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
                    // dashed forecast to empty
                    if let empty = L.empty {
                        Path { p in p.move(to: last); p.addLine(to: empty) }
                            .stroke(color.opacity(0.5),
                                    style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [2, 2.5]))
                        Circle().fill(color.opacity(0.85)).frame(width: 3, height: 3).position(empty)
                    }
                }
            }
        }
    }

    /// History points (left portion) + the empty point (bottom-right) to dash to.
    private func layout(_ size: CGSize) -> (hist: [CGPoint], empty: CGPoint?) {
        let rs = samples.map(\.r)
        guard rs.count >= 2 else { return ([], nil) }
        let yTop = max(rs.max() ?? 1, 0.15)
        func y(_ r: Double) -> CGFloat { size.height * (1 - CGFloat(min(max(r, 0), yTop) / yTop)) }

        var hShare: CGFloat = 1
        var empty: CGPoint? = nil
        if let eta, eta > 0 {
            let span = max(samples.last!.t - samples.first!.t, 1)
            hShare = max(0.42, min(0.82, CGFloat(span / (span + eta))))
            empty = CGPoint(x: size.width, y: size.height)   // 0% reached at the empty time
        }
        let histW = size.width * hShare
        let n = max(samples.count - 1, 1)
        let hist = samples.enumerated().map { i, s in
            CGPoint(x: histW * CGFloat(i) / CGFloat(n), y: y(s.r))
        }
        return (hist, empty)
    }
}
