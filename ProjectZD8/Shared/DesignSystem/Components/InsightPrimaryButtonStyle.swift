import SwiftUI

/// 主要アクション用ボタン(アクセント塗り)。画面あたり原則1つ。
struct InsightPrimaryButtonStyle: ButtonStyle {
    /// スタイルを作る。
    ///
    /// 責務: 状態を持たないスタイルを生成する。
    init() {}

    func makeBody(configuration: Configuration) -> some View {
        InsightButtonChrome(configuration: configuration, kind: .primary)
    }
}

extension ButtonStyle where Self == InsightPrimaryButtonStyle {
    /// 主要アクション用スタイル。
    static var insightPrimary: InsightPrimaryButtonStyle { InsightPrimaryButtonStyle() }
}

#Preview("Light") {
    VStack(spacing: 12) {
        Button(action: {}) { Text(verbatim: "Primary") }.buttonStyle(.insightPrimary)
        Button(action: {}) { Text(verbatim: "Secondary") }.buttonStyle(.insightSecondary)
        Button(action: {}) { Text(verbatim: "Delete") }.buttonStyle(.insightDestructive)
        Button(action: {}) { Text(verbatim: "Disabled") }.buttonStyle(.insightPrimary).disabled(true)
    }
    .padding()
    .background(InsightBackground())
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    VStack(spacing: 12) {
        Button(action: {}) { Text(verbatim: "Primary") }.buttonStyle(.insightPrimary)
        Button(action: {}) { Text(verbatim: "Secondary") }.buttonStyle(.insightSecondary)
        Button(action: {}) { Text(verbatim: "Delete") }.buttonStyle(.insightDestructive)
    }
    .padding()
    .background(InsightBackground())
    .preferredColorScheme(.dark)
}
