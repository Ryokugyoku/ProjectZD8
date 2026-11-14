#if os(macOS)
import SwiftUI

/// 車両別履歴の文脈と戻る操作を一体化した固定ヘッダーです。
struct MacOSConnectionHistoryVehicleSessionsHeader: View {
    /// 表示する車両別履歴集計です。見つからない場合は未関連付け表示を使用します。
    let group: ConnectionHistoryVehicleGroup?
    /// 画面サイズに対応する表示倍率です。
    let scale: CGFloat
    /// 車両別アーカイブへ戻る操作です。
    let back: () -> Void

    /// 幅に応じて横一列または2段の配置を選びます。
    ///
    /// 責務: 戻る操作、車両識別、履歴集計をヘッダーカードへ配置します。
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 18 * scale) {
                backButton
                MacOSConnectionHistoryVehicleSessionsIdentity(group: group, scale: scale)
                Spacer(minLength: 16 * scale)
                MacOSConnectionHistoryVehicleSessionsSummary(group: group, scale: scale)
            }

            VStack(alignment: .leading, spacing: 14 * scale) {
                HStack(spacing: 14 * scale) {
                    backButton
                    MacOSConnectionHistoryVehicleSessionsIdentity(group: group, scale: scale)
                    Spacer(minLength: 0)
                }
                Divider().opacity(0.55)
                MacOSConnectionHistoryVehicleSessionsSummary(group: group, scale: scale)
            }
        }
        .padding(20 * scale)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22 * scale, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22 * scale, style: .continuous)
                .stroke(Color.primary.opacity(0.08))
        }
    }

    /// ヘッダー内でアーカイブへ戻る操作です。
    private var backButton: some View {
        RoundedBackButton(
            accessibilityLabelKey: "history.navigation.back",
            identifier: "macos-history-vehicle-back",
            scale: scale,
            action: back
        )
    }
}
#endif
