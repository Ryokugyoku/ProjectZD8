#if os(iOS)
import UIKit

/// 記録中だけiOSの画面自動ロックを抑止します。
@MainActor
final class IOSScreenSleepInhibitor: SleepInhibitingPort {
    /// iOSのアイドルタイマー無効状態を更新する処理です。
    private let setIdleTimerDisabled: @MainActor (Bool) -> Void

    /// 画面自動ロックの抑止境界を生成します。
    ///
    /// 責務: 抑止状態をiOSのアイドルタイマー設定へ反映する境界を構築します。
    /// - Parameter setIdleTimerDisabled: `true` の間だけ画面自動ロックを抑止する更新処理。
    init(
        setIdleTimerDisabled: @escaping @MainActor (Bool) -> Void = {
            UIApplication.shared.isIdleTimerDisabled = $0
        }
    ) {
        self.setIdleTimerDisabled = setIdleTimerDisabled
    }

    /// 責務: 抑止の有効・無効をアイドルタイマー無効状態へ変換します。
    func setInhibited(_ isInhibited: Bool) {
        setIdleTimerDisabled(isInhibited)
    }
}
#endif
