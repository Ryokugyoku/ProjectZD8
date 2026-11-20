#if os(macOS)
import SwiftUI

/// macOS のセッション詳細で、Raw ログが派生値から独立していることを示します。
struct MacOSConnectionSessionDetailLineageCard: View {
    /// 画面サイズに対応する表示倍率です。
    let scale: CGFloat

    /// 分岐のアイコンと、来歴の見出し・本文を描画します。
    ///
    /// 責務: Raw ログの来歴の説明を、インディゴの淡い背景のカードとして描画します。
    var body: some View {
        HStack(spacing: 13 * scale) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 17 * scale, weight: .semibold))
                .foregroundStyle(.indigo)
            VStack(alignment: .leading, spacing: 3 * scale) {
                Text("history.training.lineage.title")
                    .font(.system(size: 12 * scale, weight: .bold))
                Text("history.training.lineage.body")
                    .font(.system(size: 11 * scale))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(17 * scale)
        .background(Color.indigo.opacity(0.07), in: RoundedRectangle(cornerRadius: 18 * scale, style: .continuous))
    }
}
#endif
