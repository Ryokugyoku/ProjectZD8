@testable import ProjectZD8

/// 車両接続中のシステムスリープ抑止通知を記録します。
@MainActor
final class VehicleConnectionSystemSleepInhibitorSpy: VehicleConnectionSystemSleepInhibiting {
    /// 通知された車両接続状態です。通知順に並びます。
    private(set) var connectionStates: [Bool] = []

    /// 空の通知履歴を生成します。
    ///
    /// 責務: スリープ抑止通知の記録先を空状態で構築します。
    init() {}

    /// 通知された車両接続状態を記録します。
    ///
    /// 責務: 1件の車両接続状態を検証用履歴へ追加します。
    /// - Parameter isActive: 通知された車両接続状態。
    func setVehicleConnectionActive(_ isActive: Bool) {
        connectionStates.append(isActive)
    }
}
