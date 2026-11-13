import SwiftUI

/// 副次アクション用ボタン(淡いアクセント面+縁)。
struct InsightSecondaryButtonStyle: ButtonStyle {
    /// スタイルを作る。
    ///
    /// 責務: 状態を持たないスタイルを生成する。
    init() {}

    func makeBody(configuration: Configuration) -> some View {
        InsightButtonChrome(configuration: configuration, kind: .secondary)
    }
}

extension ButtonStyle where Self == InsightSecondaryButtonStyle {
    /// 副次アクション用スタイル。
    static var insightSecondary: InsightSecondaryButtonStyle { InsightSecondaryButtonStyle() }
}
