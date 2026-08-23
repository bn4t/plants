import SwiftUI

enum BotanicalTheme {
    static let tint = Color.accentColor
    static let water = Color.blue
    static let feeding = Color.green
    static let attention = Color("AttentionColor")
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let elevatedSurface = Color(uiColor: .systemBackground)

    static let cardRadius: CGFloat = 22
    static let controlRadius: CGFloat = 16
}

extension View {
    func contentSurface(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(
                BotanicalTheme.elevatedSurface,
                in: RoundedRectangle(cornerRadius: BotanicalTheme.cardRadius, style: .continuous)
            )
    }
}

struct SeasonBadge: View {
    let season: Season
    var compact = false
    var overMedia = false

    var body: some View {
        Label {
            Text(season.displayName)
                .lineLimit(1)
        } icon: {
            Image(systemName: season.systemImage)
        }
        .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
        .foregroundStyle(overMedia ? Color.white : color)
        .padding(.horizontal, compact ? 9 : 11)
        .padding(.vertical, compact ? 5 : 7)
        .background(
            overMedia ? Color.black.opacity(0.52) : color.opacity(0.12),
            in: Capsule()
        )
        .accessibilityLabel("\(season.displayName) season")
    }

    var color: Color {
        switch season {
        case .spring: .green
        case .summer: .orange
        case .autumn: .brown
        case .winter: .blue
        }
    }
}

struct SeasonStrip: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let current: Season
    let intervals: SeasonalWatering?

    @ViewBuilder
    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 6) {
                ForEach(Season.allCases, id: \.self) { season in
                    accessibilityRow(for: season)
                }
            }
        } else {
            HStack(spacing: 8) {
                ForEach(Season.allCases, id: \.self) { season in
                    compactCell(for: season)
                }
            }
        }
    }

    private func compactCell(for season: Season) -> some View {
        VStack(spacing: 6) {
            Image(systemName: season.systemImage)
                .font(.body.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
            Text(season.displayName)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
            if let intervals {
                Text("\(intervals.interval(for: season))d")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(season == current ? BotanicalTheme.tint : .secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            season == current ? BotanicalTheme.tint.opacity(0.12) : Color.clear,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: season))
    }

    private func accessibilityRow(for season: Season) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(season.displayName, systemImage: season.systemImage)
                .font(.body.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(season == current ? BotanicalTheme.tint : .secondary)

            if let intervals {
                Text("\(intervals.interval(for: season)) days")
                    .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            season == current ? BotanicalTheme.tint.opacity(0.12) : Color.clear,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: season))
    }

    private func accessibilityLabel(for season: Season) -> String {
        let currentText = season == current ? ", current season" : ""
        guard let intervals else { return "\(season.displayName)\(currentText)" }
        return "\(season.displayName), initial check every \(intervals.interval(for: season)) days\(currentText)"
    }
}

struct StatusPill: View {
    let status: CareDueStatus

    var body: some View {
        Text(status.title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(background, in: Capsule())
    }

    private var foreground: Color {
        switch status {
        case .overdue: BotanicalTheme.attention
        case .today: BotanicalTheme.water
        case .upcoming: .secondary
        }
    }

    private var background: Color {
        foreground.opacity(0.12)
    }
}

struct CareToast: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let message: String
    let undo: () -> Void

    var body: some View {
        Group {
            if reduceTransparency {
                content
                    .background(
                        BotanicalTheme.elevatedSurface,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                    .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
            } else {
                content
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
            }
        }
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
    }

    private var content: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(message)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
            Spacer(minLength: 8)
            Button("Undo", action: undo)
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 54)
    }
}
