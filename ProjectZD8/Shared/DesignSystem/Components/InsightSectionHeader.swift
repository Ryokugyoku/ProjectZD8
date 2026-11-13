import SwiftUI

/// 画面内セクションの見出し(任意の補足文と右端アクセサリ付き)。
struct InsightSectionHeader<Trailing: View>: View {
    private let title: Text
    private let subtitle: Text?
    private let trailing: Trailing

    /// 見出しを作る。
    ///
    /// 責務: タイトル・補足・右端アクセサリを1行(補足は下段)に配置し、見出しトレイトを付ける。
    init(_ title: Text, subtitle: Text? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: InsightSpacing.sm) {
            VStack(alignment: .leading, spacing: InsightSpacing.xxs) {
                title
                    .font(InsightTypography.sectionTitle)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    subtitle
                        .font(InsightTypography.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: InsightSpacing.sm)
            trailing
        }
    }
}

extension InsightSectionHeader where Trailing == EmptyView {
    /// 右端アクセサリなしの見出しを作る。
    ///
    /// 責務: trailing を EmptyView にして見出しを作る。
    init(_ title: Text, subtitle: Text? = nil) {
        self.init(title, subtitle: subtitle, trailing: { EmptyView() })
    }
}

#Preview("Light") {
    InsightSectionHeader(Text(verbatim: "Recent sessions"), subtitle: Text(verbatim: "Last 7 days")) {
        Text(verbatim: "See all").font(InsightTypography.caption)
    }
    .padding()
    .background(InsightBackground())
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    InsightSectionHeader(Text(verbatim: "Recent sessions"))
        .padding()
        .background(InsightBackground())
        .preferredColorScheme(.dark)
}
