/// 車両接続中のシステムスリープ抑止状態をOS境界へ反映します。
@MainActor
protocol VehicleConnectionSystemSleepInhibiting: AnyObject {
    /// 車両接続状態に合わせてシステムスリープ抑止を切り替えます。
    ///
    /// 責務: 1件の車両接続状態をシステムスリープ抑止境界へ通知します。
    /// - Parameter isActive: 車両接続中としてスリープを抑止する場合は `true`。
    func setVehicleConnectionActive(_ isActive: Bool)
}
