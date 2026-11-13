import SwiftUI

/// 270° の円弧ゲージ。値・レンジ・任意の警告ゾーンを持つ。
///
/// 値が nil のときは充填弧も針も描かず、トラックと「—」だけを表示する(誤解を招く値を出さない)。
/// 値の変化は Reduce Motion を尊重してアニメーションする。
struct ArcGauge: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let value: Double?
    private let range: ClosedRange<Double>
    private let warningZone: ClosedRange<Double>?
    private let valueText: Text?
    private let unit: Text?
    private let label: Text?
    private let unavailableText: Text?
    private let lineWidth: CGFloat

    /// ゲージを作る。
    ///
    /// 責務: 数値と表示用 Text を保持する。valueText が nil で value がある場合は数値表示を省き読み上げのみ割合で補う。
    /// - Parameters:
    ///   - value: 現在値。欠損は nil。
    ///   - range: 表示レンジ(下限<上限)。
    ///   - warningZone: 警告ゾーン(同じ単位)。重なる部分だけ描く。
    ///   - valueText: 中央の整形済み値(例: 「6 850」)。
    ///   - unit: 値の下に出す単位。
    ///   - label: ゲージ名(下段)。
    ///   - unavailableText: 欠損時に VoiceOver が読む文言。
    ///   - lineWidth: 弧の太さ。
    init(
        value: Double?,
        range: ClosedRange<Double>,
        warningZone: ClosedRange<Double>? = nil,
        valueText: Text? = nil,
        unit: Text? = nil,
        label: Text? = nil,
        unavailableText: Text? = nil,
        lineWidth: CGFloat = 14
    ) {
        self.value = value
        self.range = range
        self.warningZone = warningZone
        self.valueText = valueText
        self.unit = unit
        self.label = label
        self.unavailableText = unavailableText
        self.lineWidth = lineWidth
    }

    private var fraction: Double? { ArcGaugeGeometry.fraction(value: value, range: range) }
    private var isInWarning: Bool {
        guard let value, let warningZone else { return false }
        return warningZone.contains(value)
    }

    var body: some View {
        ZStack {
            ArcSegmentShape(from: 0, to: 1)
                .stroke(InsightPalette.track, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

            if let zone = ArcGaugeGeometry.zoneFractions(zone: warningZone, range: range) {
                ArcSegmentShape(from: zone.lowerBound, to: zone.upperBound)
                    .stroke(InsightPalette.warning.opacity(0.55), style: StrokeStyle(lineWidth: lineWidth * 0.4, lineCap: .butt))
            }

            if let fraction {
                ArcSegmentShape(from: 0, to: fraction)
                    .stroke(
                        isInWarning ? InsightPalette.warning : InsightPalette.accent,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .insightAnimation(InsightMotion.gauge, value: fraction)
            }

            VStack(spacing: InsightSpacing.xxs) {
                if let valueText, fraction != nil {
                    valueText
                        .font(InsightTypography.metricValueLarge)
                        .minimumScaleFactor(0.4)
                        .lineLimit(1)
                } else if fraction == nil {
                    Text(verbatim: "—")
                        .font(InsightTypography.metricValueLarge)
                        .foregroundStyle(.tertiary)
                        .accessibilityLabel(unavailableText ?? Text(verbatim: "—"))
                }
                if fraction != nil, let unit {
                    unit.font(InsightTypography.metricUnit).foregroundStyle(.secondary)
                }
                if let label {
                    label.font(InsightTypography.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(.horizontal, lineWidth * 1.5)
            .accessibilityElement(children: .combine)
        }
        .aspectRatio(1, contentMode: .fit)
        .padding(lineWidth / 2)
        .accessibilityElement(children: .contain)
        .modifier(GaugeAccessibilityValue(valueText: valueText, fraction: fraction))
    }
}

/// valueText が無いときだけ割合を VoiceOver 用の値として付与する。
private struct GaugeAccessibilityValue: ViewModifier {
    let valueText: Text?
    let fraction: Double?

    func body(content: Content) -> some View {
        if valueText == nil, let fraction {
            content.accessibilityValue(Text(fraction, format: .percent.precision(.fractionLength(0))))
        } else {
            content
        }
    }
}

/// 270° 弧の部分区間(割合 from...to)を描く Shape。割合はアニメーション可能。
private struct ArcSegmentShape: Shape {
    var from: Double
    var to: Double

    var animatableData: Double {
        get { to }
        set { to = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        guard to > from else { return path }
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: radius,
            startAngle: .degrees(ArcGaugeGeometry.degrees(forFraction: from)),
            endAngle: .degrees(ArcGaugeGeometry.degrees(forFraction: to)),
            clockwise: false
        )
        return path
    }
}

#Preview("Light") {
    HStack(spacing: 24) {
        ArcGauge(value: 6850, range: 0...9000, warningZone: 7500...9000, valueText: Text(verbatim: "6 850"),
                 unit: Text(verbatim: "rpm"), label: Text(verbatim: "Engine"))
        ArcGauge(value: nil, range: 0...9000, label: Text(verbatim: "Engine"))
    }
    .frame(height: 200)
    .padding()
    .background(InsightBackground())
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    ArcGauge(value: 8200, range: 0...9000, warningZone: 7500...9000, valueText: Text(verbatim: "8 200"),
             unit: Text(verbatim: "rpm"))
        .frame(width: 220, height: 220)
        .padding()
        .background(InsightBackground())
        .preferredColorScheme(.dark)
}
