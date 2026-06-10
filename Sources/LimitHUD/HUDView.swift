import SwiftUI

/// Floating quota card, styled per the Framea Design System.
/// Compact · solid dark surface · mono uppercase system labels · semantic quota ramp.
struct HUDView: View {
    @ObservedObject var store: QuotaStore
    @ObservedObject private var settings = Settings.shared
    var onClose: () -> Void = {}
    var onSettings: () -> Void = {}

    // tick the countdowns every second without re-fetching
    @State private var now = Date()
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            header
            VStack(alignment: .leading, spacing: 11) {
                ForEach(store.providers) { provider in
                    let visible = provider.windows.filter {
                        !settings.hiddenWindows.contains("\(provider.name)/\($0.label)")
                    }
                    if provider.error != nil || !visible.isEmpty {
                        ProviderSection(provider: provider, windows: visible)
                    }
                }
            }
            divider
            footer
        }
        .padding(12)
        .frame(width: 206, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.border2, lineWidth: 1)
        )
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.05), .clear],
                        startPoint: .top, endPoint: .center
                    )
                )
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
        }
        .opacity(settings.opacity)
        .onReceive(ticker) { now = $0 }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(Theme.success)
                .frame(width: 5, height: 5)
                .shadow(color: Theme.success.opacity(0.6), radius: 3)
            Text("AI QUOTA").monoLabel(size: 9.5, tracking: 1.6, color: Theme.muted)
            Spacer(minLength: 6)
            iconButton("arrow.clockwise", spinning: store.isRefreshing) { store.refresh() }
            iconButton("gearshape") { onSettings() }
            iconButton("xmark") { onClose() }
        }
    }

    private func iconButton(_ system: String, spinning: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Theme.muted)
                .frame(width: 19, height: 19)
                .background(Color.white.opacity(0.001))
                .rotationEffect(.degrees(spinning ? 360 : 0))
                .animation(spinning ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: spinning)
        }
        .buttonStyle(IconButtonStyle())
    }

    // MARK: Footer

    private var divider: some View {
        Rectangle().fill(Theme.border).frame(height: 1)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if let last = store.lastUpdated {
                Text("SYNCED \(timeString(last))")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundColor(Theme.muted2)
            }
            Spacer(minLength: 6)
            Text("⌘⇧L")
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundColor(Theme.muted2)
                .padding(.horizontal, 4.5)
                .padding(.vertical, 1)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.border2, lineWidth: 1))
        }
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}

// MARK: - Provider block

private struct ProviderSection: View {
    let provider: ProviderQuota
    let windows: [QuotaWindow]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(provider.name.uppercased())
                .monoLabel(size: 9, tracking: 1.8, color: Theme.muted2)

            if let error = provider.error {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 8.5))
                    Text(error)
                        .font(.system(size: 10.5, weight: .medium))
                }
                .foregroundColor(Theme.warning)
            } else {
                ForEach(windows) { window in
                    QuotaRow(window: window)
                }
            }
        }
    }
}

// MARK: - One quota window

private struct QuotaRow: View {
    let window: QuotaWindow

    private var color: Color { Theme.quotaColor(remaining: window.remaining) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(window.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.inkDim)
                Spacer(minLength: 6)
                (
                    Text("\(Int(window.remaining * 100))%")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(color)
                    +
                    Text(" left")
                        .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                        .foregroundColor(Theme.muted2)
                )
                if let cd = window.resetCountdown {
                    Text(cd)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundColor(Theme.muted2)
                }
            }
            ProgressBar(value: window.remaining, color: color)
        }
    }
}

private struct ProgressBar: View {
    let value: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.trackBg)
                Capsule()
                    .fill(color)
                    .frame(width: max(3, geo.size.width * min(1, max(0, value))))
                    .shadow(color: color.opacity(0.45), radius: 2.5, y: 0)
            }
        }
        .frame(height: 4)
    }
}

// MARK: - Button style

private struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(configuration.isPressed ? Theme.hoverFill : Color.clear)
            )
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
