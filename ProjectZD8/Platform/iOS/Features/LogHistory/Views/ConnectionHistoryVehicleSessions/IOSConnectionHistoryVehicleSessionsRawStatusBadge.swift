#if os(iOS)
import SwiftUI

/// Rawログの保管状態を一覧行で示すバッジです。
struct IOSConnectionHistoryVehicleSessionsRawStatusBadge: View {
    /// 表示するバッジ内容です。
    let badge: ConnectionHistoryRawStatusBadge

    /// アイコン、文言、色調の色を持つラベルを描画します。
    ///
    /// 責務: 1件のバッジ内容をアイコン、文言、トーン色を持つラベルへ配置します。
    var body: some View {
        Label(LocalizedStringKey(badge.titleKey), systemImage: badge.systemImage)
            .font(.caption2.weight(.bold))
            .foregroundStyle(badge.tone.color)
    }
}
#endif
