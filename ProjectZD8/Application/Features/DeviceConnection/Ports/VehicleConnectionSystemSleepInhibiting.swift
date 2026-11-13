/// 車両接続中の端末アイドル移行抑止状態をOS境界へ反映します。
@MainActor
protocol VehicleConnectionSystemSleepInhibiting: AnyObject {
    /// 車両接続状態に合わせて端末固有のアイドル移行抑止を切り替えます。
    ///
    /// 責務: 1件の車両接続状態を端末固有のアイドル移行抑止境界へ通知します。
    /// - Parameter isActive: 車両接続中としてアイドル移行を抑止する場合は `true`。
    func setVehicleConnectionActive(_ isActive: Bool)
}
