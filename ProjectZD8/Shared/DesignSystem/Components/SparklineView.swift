import SwiftUI

/// 値の推移を描く軽量な折れ線/エリア。nil(欠損)は線を繋がず隙間のまま残す。
struct SparklineView: View {
    /// 描画スタイル。
    enum Style {
        case line
        case area
    }

    private let values: [Double?]
    private let range: ClosedRange<Double>?
    private let style: Style
    private let tint: Color
    private let accessibilityLabelText: Text
    private let accessibilityValueText: Text?

    /// スパークラインを作る。
    ///
    /// 責務: 値列と見た目・読み上げ文言を保持する。
    /// - Parameters:
    ///   - values: 等間隔サンプル。欠損は nil。
    ///   - range: 縦軸レンジ。nil なら有限値の最小〜最大。
    ///   - accessibilityLabel: 何の推移か(例: 「冷却水温の推移」)。
    ///   - accessibilityValue: 読み上げ用の要約(例: 「最小 80、最大 92」)。
    init(
        values: [Double?],
        range: ClosedRange<Double>? = nil,
        style: Style = .line,
        tint: Color = InsightPalette.accent,
        accessibilityLabel: Text,
        accessibilityValue: Text? = nil
    ) {
        self.values = values
        self.range = range
        self.style = style
        self.tint = tint
        self.accessibilityLabelText = accessibilityLabel
        self.accessibilityValueText = accessibilityValue
    }

    var body: some View {
        Canvas { context, size in
            guard let resolved = SparklineGeometry.resolvedRange(values: values, explicit: range) else { return }
            let inset: CGFloat = 2
            let drawSize = CGSize(width: max(0, size.width - inset * 2), height: max(0, size.height - inset * 2))
            let segments = SparklineGeometry.segments(values: values, range: resolved, size: drawSize)
            let offset = CGAffineTransform(translationX: inset, y: inset)

            for segment in segments {
                let points = segment.points.map { $0.applying(offset) }
                guard let first = points.first else { continue }
                if points.count == 1 {
                    let dot = CGRect(x: first.x - 2, y: first.y - 2, width: 4, height: 4)
                    context.fill(Path(ellipseIn: dot), with: .color(tint))
                    continue
                }
                var line = Path()
                line.addLines(points)
                if style == .area, let last = points.last {
                    var area = line
                    area.addLine(to: CGPoint(x: last.x, y: size.height - inset))
                    area.addLine(to: CGPoint(x: first.x, y: size.height - inset))
                    area.closeSubpath()
                    context.fill(
                        area,
                        with: .linearGradient(
                            Gradient(colors: [tint.opacity(0.35), tint.opacity(0.02)]),
                            startPoint: CGPoint(x: 0, y: 0),
                            endPoint: CGPoint(x: 0, y: size.height)
                        )
                    )
                }
                context.stroke(line, with: .color(tint), style: StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round))
            }
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabelText)
        .modifier(OptionalAccessibilityValue(text: accessibilityValueText))
        .accessibilityAddTraits(.isImage)
    }
}

/// 読み上げ値が与えられたときだけ accessibilityValue を付ける。
private struct OptionalAccessibilityValue: ViewModifier {
    let text: Text?

    func body(content: Content) -> some View {
        if let text { content.accessibilityValue(text) } else { content }
    }
}

#Preview("Light") {
    VStack(spacing: 16) {
        SparklineView(values: [1, 3, 2, nil, nil, 4, 6, 5, nil, 7], style: .area, accessibilityLabel: Text(verbatim: "Trend"))
            .frame(height: 60)
        SparklineView(values: [1, nil, 2, nil, 3], accessibilityLabel: Text(verbatim: "Sparse"))
            .frame(height: 40)
        SparklineView(values: [nil, nil], accessibilityLabel: Text(verbatim: "Empty"))
            .frame(height: 40)
    }
    .padding()
    .background(InsightBackground())
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    SparklineView(values: [1, 3, 2, nil, 5, 4, 6], style: .area, tint: InsightPalette.series(1),
                  accessibilityLabel: Text(verbatim: "Trend"))
        .frame(height: 60)
        .padding()
        .background(InsightBackground())
        .preferredColorScheme(.dark)
}
