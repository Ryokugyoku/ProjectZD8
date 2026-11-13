import SwiftUI

/// 状態を示す小さなバッジ。色に加えシンボルでも意味を伝える。
struct StatusBadge: View {
    private let text: Text
    private let tone: StatusTone
    private let symbol: String?

    /// バッジを作る。
    ///
    /// 責務: 文言・トーン・シンボル(省略時はトーン既定)を保持する。
    init(_ text: Text, tone: StatusTone = .neutral, symbol: String? = nil) {
        self.text = text
        self.tone = tone
        self.symbol = symbol
    }

    var body: some View {
        HStack(spacing: InsightSpacing.xs) {
            Image(systemName: symbol ?? tone.defaultSymbol)
                .imageScale(.small)
                .accessibilityHidden(true)
            text.lineLimit(1)
        }
        .font(InsightTypography.badge)
        .foregroundStyle(tone.color)
        .padding(.horizontal, InsightSpacing.sm)
        .padding(.vertical, InsightSpacing.xs)
        .background(Capsule().fill(tone.color.opacity(0.14)))
        .accessibilityElement(children: .combine)
    }
}

#Preview("Light") {
    VStack(alignment: .leading, spacing: 8) {
        ForEach(StatusTone.allCases, id: \.self) { StatusBadge(Text(verbatim: "\($0)"), tone: $0) }
    }
    .padding()
    .background(InsightBackground())
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    VStack(alignment: .leading, spacing: 8) {
        ForEach(StatusTone.allCases, id: \.self) { StatusBadge(Text(verbatim: "\($0)"), tone: $0) }
    }
    .padding()
    .background(InsightBackground())
    .preferredColorScheme(.dark)
}
