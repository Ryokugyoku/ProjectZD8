import SwiftUI

/// 横方向の充填メーター。値が nil のときはトラックだけを描く。
struct LinearMeter: View {
    private let value: Double?
    private let range: ClosedRange<Double>
    private let warningZone: ClosedRange<Double>?
    private let tint: Color
    private let height: CGFloat
    private let label: Text?
    private let valueText: Text?

    /// メーターを作る。
    ///
    /// 責務: 値・レンジ・警告ゾーン・読み上げ文言を保持する。
    /// - Parameters:
    ///   - label: 読み上げ用の名称(例: 「スロットル開度」)。
    ///   - valueText: 読み上げ用の整形済み値。nil なら割合を読む。
    init(
        value: Double?,
        range: ClosedRange<Double> = 0...1,
        warningZone: ClosedRange<Double>? = nil,
        tint: Color = InsightPalette.accent,
        height: CGFloat = 8,
        label: Text? = nil,
        valueText: Text? = nil
    ) {
        self.value = value
        self.range = range
        self.warningZone = warningZone
        self.tint = tint
        self.height = height
        self.label = label
        self.valueText = valueText
    }

    private var fraction: Double? { ArcGaugeGeometry.fraction(value: value, range: range) }
    private var isInWarning: Bool {
        guard let value, let warningZone else { return false }
        return warningZone.contains(value)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(InsightPalette.track)
                if let zone = ArcGaugeGeometry.zoneFractions(zone: warningZone, range: range) {
                    Rectangle()
                        .fill(InsightPalette.warning.opacity(0.35))
                        .frame(width: width * (zone.upperBound - zone.lowerBound))
                        .offset(x: width * zone.lowerBound)
                        .clipShape(Capsule())
                }
                if let fraction {
                    Capsule()
                        .fill(isInWarning ? InsightPalette.warning : tint)
                        .frame(width: max(height, width * fraction))
                        .insightAnimation(InsightMotion.gauge, value: fraction)
                }
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .modifier(MeterAccessibility(label: label, valueText: valueText, fraction: fraction))
    }
}

/// メーターの読み上げ属性(ラベルと値)を付与する。
private struct MeterAccessibility: ViewModifier {
    let label: Text?
    let valueText: Text?
    let fraction: Double?

    func body(content: Content) -> some View {
        let labelled = Group {
            if let label { content.accessibilityLabel(label) } else { content }
        }
        if let valueText, fraction != nil {
            labelled.accessibilityValue(valueText)
        } else if let fraction {
            labelled.accessibilityValue(Text(fraction, format: .percent.precision(.fractionLength(0))))
        } else {
            labelled
        }
    }
}

#Preview("Light") {
    VStack(spacing: 16) {
        LinearMeter(value: 0.35)
        LinearMeter(value: 0.9, warningZone: 0.8...1)
        LinearMeter(value: nil)
    }
    .padding()
    .background(InsightBackground())
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    LinearMeter(value: 6, range: 0...10, warningZone: 8...10)
        .padding()
        .background(InsightBackground())
        .preferredColorScheme(.dark)
}
