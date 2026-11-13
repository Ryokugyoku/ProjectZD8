import SwiftUI

/// 内容を載せる標準コンテナ。ガラスではなく控えめな面+縁で内容を主役にする。
///
/// 見出し(任意)と右端のアクセサリ(任意)を持つ。
struct InsightCard<Trailing: View, Content: View>: View {
    @Environment(\.colorSchemeContrast) private var contrast

    private let title: Text?
    private let trailing: Trailing
    private let content: Content

    /// 見出し・右端アクセサリ付きのカードを作る。
    ///
    /// 責務: 見出し行(title と trailing のどちらかがあれば表示)と本文を縦に並べる。
    init(
        title: Text? = nil,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: InsightSpacing.md) {
            if title != nil || Trailing.self != EmptyView.self {
                HStack(alignment: .firstTextBaseline, spacing: InsightSpacing.sm) {
                    if let title {
                        title
                            .font(InsightTypography.sectionTitle)
                            .accessibilityAddTraits(.isHeader)
                    }
                    Spacer(minLength: InsightSpacing.sm)
                    trailing
                }
            }
            content
        }
        .padding(InsightSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: InsightRadius.md, style: .continuous)
                .fill(InsightPalette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: InsightRadius.md, style: .continuous)
                .strokeBorder(InsightPalette.border(for: contrast), lineWidth: 1)
        )
    }
}

extension InsightCard where Trailing == EmptyView {
    /// 右端アクセサリなしのカードを作る。
    ///
    /// 責務: trailing を EmptyView にして見出しと本文だけを表示する。
    init(title: Text? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, trailing: { EmptyView() }, content: content)
    }
}

#Preview("Light") {
    InsightCard(title: Text(verbatim: "Engine"), trailing: { StatusBadge(Text(verbatim: "OK"), tone: .positive) }) {
        Text(verbatim: "Content").font(InsightTypography.body)
    }
    .padding()
    .background(InsightBackground())
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    InsightCard(title: Text(verbatim: "Engine")) {
        Text(verbatim: "Content").font(InsightTypography.body)
    }
    .padding()
    .background(InsightBackground())
    .preferredColorScheme(.dark)
}
