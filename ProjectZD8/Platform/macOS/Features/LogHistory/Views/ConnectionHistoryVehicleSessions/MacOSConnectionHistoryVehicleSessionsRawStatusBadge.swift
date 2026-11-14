#if os(macOS)
import SwiftUI

/// セッション行に並べるRaw保管状態(iCloud転送またはローカル保存)のバッジです。
struct MacOSConnectionHistoryVehicleSessionsRawStatusBadge: View {
    /// Applicationが状態から導出したバッジ内容です。
    let badge: ConnectionHistoryRawStatusBadge
    /// 画面サイズに対応する表示倍率です。
    let scale: CGFloat

    /// アイコン、文言、トーン色のラベルを描画します。
    ///
    /// 責務: 1件のバッジ内容をmacOSの表示色付きラベルへ変換します。
    var body: some View {
        Label(LocalizedStringKey(badge.titleKey), systemImage: badge.systemImage)
            .font(.system(size: 8.5 * scale, weight: .bold))
            .foregroundStyle(badge.tone.color)
    }
}
#endif
