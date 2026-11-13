#if os(macOS)
import Foundation

/// 記録中だけ、ディスプレイ消灯は妨げずにmacOSのシステムスリープを抑止します。
@MainActor
final class MacOSSystemSleepInhibitor: SleepInhibitingPort {
    /// システムスリープを抑止している `ProcessInfo` のアクティビティです。
    private var activity: NSObjectProtocol?

    /// 未抑止状態の境界を生成します。
    ///
    /// 責務: システムスリープ抑止境界を未開始状態で構築します。
    init() {}

    /// 責務: 抑止の有効・無効を、重複しない `ProcessInfo` アクティビティの開始・終了へ変換します。
    func setInhibited(_ isInhibited: Bool) {
        if isInhibited {
            guard activity == nil else { return }
            activity = ProcessInfo.processInfo.beginActivity(
                options: .idleSystemSleepDisabled,
                reason: "RevTorque Insight is recording"
            )
        } else if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
    }
}
#endif
