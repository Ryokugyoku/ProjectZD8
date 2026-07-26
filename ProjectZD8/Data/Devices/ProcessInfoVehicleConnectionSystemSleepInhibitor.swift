import Foundation

/// 車両接続中だけディスプレイ消灯を妨げずにシステムスリープを抑止します。
@MainActor
final class ProcessInfoVehicleConnectionSystemSleepInhibitor: VehicleConnectionSystemSleepInhibiting {
    /// システムスリープを抑止しているProcessInfoアクティビティです。
    private var activity: NSObjectProtocol?

    /// 未抑止状態のProcessInfo境界を生成します。
    ///
    /// 責務: 車両接続用システムスリープ抑止境界を未開始状態で構築します。
    init() {}

    /// 車両接続状態に合わせてProcessInfoアクティビティを開始または終了します。
    ///
    /// 責務: 1件の車両接続状態を重複しないシステムスリープ抑止へ変換します。
    /// - Parameter isActive: システムスリープ抑止を保持する場合は `true`。
    func setVehicleConnectionActive(_ isActive: Bool) {
        if isActive {
            guard activity == nil else { return }
            activity = ProcessInfo.processInfo.beginActivity(
                options: .idleSystemSleepDisabled,
                reason: "RevTorque Insight vehicle connection is active"
            )
        } else if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
    }
}
