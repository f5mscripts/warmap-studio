import SwiftUI

/// Reusable controls shared by the dashboard, the wizard and the editor.

/// A raised panel with the app's card treatment.
struct Panel<Content: View>: View {
    var padding: CGFloat = Theme.Metric.gutter
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: Theme.Metric.corner, style: .continuous)
                    .fill(Theme.Palette.slate)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Metric.corner, style: .continuous)
                    .strokeBorder(Theme.Palette.rule, lineWidth: Theme.Metric.hairline)
            )
    }
}

/// The primary action button: gold leaf on charcoal.
struct GoldButtonStyle: ButtonStyle {
    var isProminent: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Font.ui(15, weight: .semibold))
            .foregroundStyle(isProminent ? Theme.Palette.textOnLight : Theme.Palette.gold)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background {
                RoundedRectangle(cornerRadius: Theme.Metric.cornerSmall, style: .continuous)
                    .fill(isProminent ? AnyShapeStyle(Theme.goldLeaf)
                                      : AnyShapeStyle(Theme.Palette.graphite))
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Metric.cornerSmall, style: .continuous)
                    .strokeBorder(isProminent ? .clear : Theme.Palette.goldDim,
                                  lineWidth: Theme.Metric.hairline)
            }
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(Theme.Motion.quick, value: configuration.isPressed)
    }
}

/// A small icon button used across the toolbar and cards.
struct IconButton: View {
    let systemName: String
    var label: String
    var tint: Color = Theme.Palette.textSecondary
    var isActive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 34, height: 34)
                .foregroundStyle(isActive ? Theme.Palette.textOnLight : tint)
                .background {
                    RoundedRectangle(cornerRadius: Theme.Metric.cornerSmall, style: .continuous)
                        .fill(isActive ? AnyShapeStyle(Theme.goldLeaf)
                                       : AnyShapeStyle(Color.clear))
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// A section heading with a hairline rule, used down the left of the dashboard.
struct SectionHeader: View {
    let title: String
    var trailing: AnyView?

    init(_ title: String) {
        self.title = title
        self.trailing = nil
    }

    init<T: View>(_ title: String, @ViewBuilder trailing: () -> T) {
        self.title = title
        self.trailing = AnyView(trailing())
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Metric.gutterTight) {
            Text(title)
                .font(Theme.Font.label)
                .tracking(1.6)
                .foregroundStyle(Theme.Palette.gold)
            Rectangle()
                .fill(Theme.Palette.rule)
                .frame(height: 1)
            if let trailing { trailing }
        }
    }
}

/// Shown when a list has nothing in it — never a blank screen.
struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Theme.Metric.gutter) {
            Image(systemName: systemImage)
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(Theme.Palette.goldDim)
            Text(title)
                .font(Theme.Font.sectionTitle)
                .foregroundStyle(Theme.Palette.textPrimary)
            Text(message)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(GoldButtonStyle())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Metric.gutterLoose * 2)
    }
}

/// The autosave indicator.
struct SaveIndicator: View {
    let state: EditorStore.SaveState

    var body: some View {
        HStack(spacing: 6) {
            switch state {
            case .saving:
                ProgressView().controlSize(.mini).tint(Theme.Palette.gold)
            case .saved:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.Palette.success)
            case .unsaved:
                Image(systemName: "circle.dotted")
                    .foregroundStyle(Theme.Palette.textTertiary)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.Palette.danger)
            }
            Text(state.label)
                .font(Theme.Font.caption)
                .foregroundStyle(state == .saved
                                 ? Theme.Palette.textTertiary
                                 : Theme.Palette.textSecondary)
        }
        .animation(Theme.Motion.quick, value: state)
    }
}

/// A swatch showing a country's colour and flag together.
struct CountryChip: View {
    let country: Country
    var date: HistoricalDate?
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            FlagView(country: country, date: date ?? HistoricalDate(year: 1939))
                .frame(width: 26, height: 17)
                .clipShape(RoundedRectangle(cornerRadius: 2))
                .overlay(RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(Theme.Palette.rule, lineWidth: 0.5))
            Text(country.name)
                .font(Theme.Font.ui(13, weight: .medium))
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(1)
            Circle()
                .fill(Color(hexString: country.colorHex) ?? Theme.Palette.textTertiary)
                .frame(width: 9, height: 9)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: Theme.Metric.cornerSmall)
                .fill(isSelected ? Theme.Palette.graphite : Theme.Palette.slate)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Metric.cornerSmall)
                .strokeBorder(isSelected ? Theme.Palette.gold : Theme.Palette.rule,
                              lineWidth: isSelected ? 1.5 : 0.5)
        )
    }
}

/// Draws a country's flag for a date, using the procedural flag renderer.
struct FlagView: View {
    let country: Country
    let date: HistoricalDate

    var body: some View {
        Canvas { context, size in
            guard let flag = country.flag(on: date) else { return }
            context.withCGContext { cgContext in
                FlagRenderer.draw(flag.spec,
                                  in: CGRect(origin: .zero, size: size),
                                  context: cgContext)
            }
        }
        .accessibilityLabel("\(country.name) flag")
    }
}
