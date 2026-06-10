import SwiftUI

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

    @State private var now = Date()
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var s: CGFloat { settings.cardScale }
    private var cardBg: Color { settings.cardBgCustom ? settings.cardBgColor : Theme.surface }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 11 * s) {
            header
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
        .background(cardBg, in: RoundedRectangle(cornerRadius: 14 * s, style: .continuous))
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
    }

    private var header: some View {
        HStack(spacing: 7 * s) {
            Circle().fill(Theme.success).frame(width: 5 * s, height: 5 * s)
                .shadow(color: Theme.success.opacity(0.6), radius: 3)
            Text("AI QUOTA").monoLabel(size: 9.5 * s, tracking: 1.6 * s, color: p.muted)
            Spacer(minLength: 6 * s)
            iconButton("arrow.clockwise", spinning: store.isRefreshing) { store.refresh() }
            iconButton("gearshape") { onSettings() }
            iconButton("xmark") { onClose() }
        }
    }

    private func iconButton(_ system: String, spinning: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 10 * s, weight: .medium))
                .foregroundColor(p.muted)
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

private struct ProviderSection: View {
    let provider: ProviderQuota
    let windows: [QuotaWindow]
    let s: CGFloat
    let p: CardPalette
    let bar: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 7 * s) {
            Text(provider.name.uppercased())
                .monoLabel(size: 9 * s, tracking: 1.8 * s, color: p.muted2)
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
            }
        }
        .frame(height: 4 * s)
    }
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
