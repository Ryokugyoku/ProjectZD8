#if os(iOS)
import UIKit

/// 車両接続中だけiOSの画面自動ロックを抑止します。
@MainActor
final class IOSVehicleConnectionScreenSleepInhibitor: VehicleConnectionSystemSleepInhibiting {
    /// iOSのアイドルタイマー無効状態を更新する処理です。
    private let setIdleTimerDisabled: @MainActor (Bool) -> Void

    /// iOSの画面自動ロック境界を生成します。
    ///
    /// 責務: 車両接続状態をiOSのアイドルタイマー設定へ反映する境界を構築します。
    /// - Parameter setIdleTimerDisabled: `true` の間だけ画面自動ロックを抑止する更新処理。
    init(
        setIdleTimerDisabled: @escaping @MainActor (Bool) -> Void = {
            UIApplication.shared.isIdleTimerDisabled = $0
        }
    ) {
        self.setIdleTimerDisabled = setIdleTimerDisabled
    }

    /// 車両接続状態に合わせてiOSの画面自動ロック抑止を切り替えます。
    ///
    /// 責務: 1件の車両接続状態をiOSのアイドルタイマー無効状態へ変換します。
    /// - Parameter isActive: 画面自動ロックを抑止する場合は `true`。
    func setVehicleConnectionActive(_ isActive: Bool) {
        setIdleTimerDisabled(isActive)
    }
}
#endif
