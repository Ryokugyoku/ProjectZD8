import SwiftUI

/// 計測値を大きく見せるタイル(ラベル・値・単位・傾向/補足・陳腐化表示)。
///
/// 値が nil のときは「—」を出し、数値を捏造しない。陳腐化(最新でない)値は薄く表示し `staleText` を添える。
struct MetricTile: View {
    @Environment(\.colorSchemeContrast) private var contrast

    private let label: Text
    private let value: Text?
    private let unit: Text?
    private let secondary: Text?
    private let trend: MetricTrend?
    private let isStale: Bool
    private let staleText: Text?
    private let unavailableText: Text?

    /// タイルを作る。
    ///
    /// 責務: 表示用の Text 群を保持する。value が nil なら欠損表示になる。
    /// - Parameters:
    ///   - unavailableText: 欠損時に VoiceOver が読む文言(例: 「データなし」)。
    ///   - staleText: 陳腐化時に表示・読み上げる文言(例: 「更新が止まっています」)。
    init(
        label: Text,
        value: Text?,
        unit: Text? = nil,
        secondary: Text? = nil,
        trend: MetricTrend? = nil,
        isStale: Bool = false,
        staleText: Text? = nil,
        unavailableText: Text? = nil
    ) {
        self.label = label
        self.value = value
        self.unit = unit
        self.secondary = secondary
        self.trend = trend
        self.isStale = isStale
        self.staleText = staleText
        self.unavailableText = unavailableText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: InsightSpacing.xs) {
            label
                .font(InsightTypography.label)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(alignment: .firstTextBaseline, spacing: InsightSpacing.xs) {
                if let value {
                    value
                        .font(InsightTypography.metricValueLarge)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                } else {
                    Text(verbatim: "—")
                        .font(InsightTypography.metricValueLarge)
                        .foregroundStyle(.tertiary)
                        .accessibilityLabel(unavailableText ?? Text(verbatim: "—"))
                }
                if value != nil, let unit {
                    unit
                        .font(InsightTypography.metricUnit)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .opacity(isStale ? 0.5 : 1)

            if let trend {
                HStack(spacing: InsightSpacing.xxs) {
                    Image(systemName: trend.direction.symbol).imageScale(.small)
                    trend.text
                }
                .font(InsightTypography.caption)
                .foregroundStyle(trend.tone == .neutral ? AnyShapeStyle(.secondary) : AnyShapeStyle(trend.tone.color))
            }
            if let secondary {
                secondary
                    .font(InsightTypography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if isStale, let staleText {
                HStack(spacing: InsightSpacing.xxs) {
                    Image(systemName: "clock.badge.exclamationmark").imageScale(.small)
                    staleText
                }
                .font(InsightTypography.footnote)
                .foregroundStyle(InsightPalette.warning)
            }
        }
        .padding(InsightSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: InsightRadius.sm, style: .continuous)
                .fill(InsightPalette.surfaceRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: InsightRadius.sm, style: .continuous)
                .strokeBorder(InsightPalette.border(for: contrast), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

#Preview("Light") {
    Grid(horizontalSpacing: 12, verticalSpacing: 12) {
        GridRow {
            MetricTile(label: Text(verbatim: "Speed"), value: Text(verbatim: "92"), unit: Text(verbatim: "km/h"),
                       trend: MetricTrend(.up, text: Text(verbatim: "+4"), tone: .active))
            MetricTile(label: Text(verbatim: "Coolant"), value: Text(verbatim: "88.5"), unit: Text(verbatim: "°C"),
                       secondary: Text(verbatim: "Normal"), isStale: true, staleText: Text(verbatim: "Stale"))
        }
        GridRow {
            MetricTile(label: Text(verbatim: "Boost"), value: nil, unit: Text(verbatim: "kPa"))
            MetricTile(label: Text(verbatim: "Intake"), value: Text(verbatim: "31"), unit: Text(verbatim: "°C"))
        }
    }
    .padding()
    .background(InsightBackground())
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    MetricTile(label: Text(verbatim: "RPM"), value: Text(verbatim: "6 850"), unit: Text(verbatim: "rpm"),
               trend: MetricTrend(.down, text: Text(verbatim: "-120"), tone: .warning))
        .padding()
        .background(InsightBackground())
        .preferredColorScheme(.dark)
}
