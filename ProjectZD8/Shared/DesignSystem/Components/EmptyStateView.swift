import SwiftUI

/// データなし・未接続・失敗などの状態を説明する空状態表示(シンボル・タイトル・説明・任意アクション)。
struct EmptyStateView: View {
    private let symbol: String
    private let title: Text
    private let message: Text?
    private let action: InsightAction?

    /// 空状態を作る。
    ///
    /// 責務: シンボル・文言・任意のアクションを縦に中央揃えで並べる。
    init(symbol: String, title: Text, message: Text? = nil, action: InsightAction? = nil) {
        self.symbol = symbol
        self.title = title
        self.message = message
        self.action = action
    }

    var body: some View {
        VStack(spacing: InsightSpacing.md) {
            Image(systemName: symbol)
                .font(.system(.largeTitle, design: .rounded, weight: .regular))
                .foregroundStyle(InsightPalette.accent)
                .accessibilityHidden(true)
            VStack(spacing: InsightSpacing.xs) {
                title
                    .font(InsightTypography.sectionTitle)
                    .multilineTextAlignment(.center)
                if let message {
                    message
                        .font(InsightTypography.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .accessibilityElement(children: .combine)
            if let action {
                Button(action: action.handler) { action.title }
                    .buttonStyle(.insightSecondary)
                    .padding(.top, InsightSpacing.xs)
            }
        }
        .padding(InsightSpacing.xl)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity)
    }
}

#Preview("Light") {
    EmptyStateView(
        symbol: "car.side",
        title: Text(verbatim: "No vehicles yet"),
        message: Text(verbatim: "Add a vehicle to start recording."),
        action: InsightAction(Text(verbatim: "Add vehicle")) {}
    )
    .background(InsightBackground())
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    EmptyStateView(symbol: "antenna.radiowaves.left.and.right.slash", title: Text(verbatim: "Not connected"))
        .background(InsightBackground())
        .preferredColorScheme(.dark)
}
