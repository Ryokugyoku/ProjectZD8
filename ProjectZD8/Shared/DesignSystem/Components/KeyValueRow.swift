import SwiftUI

/// キーと値を1行で見せる行。Dynamic Type が大きく収まらないときは縦積みに切り替える。
struct KeyValueRow: View {
    private let key: Text
    private let value: Text
    private let isNumeric: Bool

    /// 行を作る。
    ///
    /// 責務: キー・値を保持する。数値の場合は rounded+等幅数字で表示する。
    init(_ key: Text, value: Text, isNumeric: Bool = false) {
        self.key = key
        self.value = value
        self.isNumeric = isNumeric
    }

    private var valueFont: Font {
        isNumeric ? InsightTypography.metricValueSmall : InsightTypography.body
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: InsightSpacing.md) {
                key.font(InsightTypography.body).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: InsightSpacing.sm)
                value.font(valueFont).lineLimit(1)
            }
            VStack(alignment: .leading, spacing: InsightSpacing.xxs) {
                key.font(InsightTypography.caption).foregroundStyle(.secondary)
                value.font(valueFont)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Light") {
    InsightCard(title: Text(verbatim: "Details")) {
        KeyValueRow(Text(verbatim: "Model"), value: Text(verbatim: "ZD8"))
        Divider()
        KeyValueRow(Text(verbatim: "Odometer"), value: Text(verbatim: "48 213 km"), isNumeric: true)
    }
    .padding()
    .background(InsightBackground())
    .preferredColorScheme(.light)
}

#Preview("Dark Large Type") {
    KeyValueRow(Text(verbatim: "Odometer"), value: Text(verbatim: "48 213 km"), isNumeric: true)
        .padding()
        .background(InsightBackground())
        .environment(\.dynamicTypeSize, .accessibility3)
        .preferredColorScheme(.dark)
}
