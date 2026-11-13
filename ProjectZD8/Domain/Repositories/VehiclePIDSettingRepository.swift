import Foundation

/// 車両ごとのPID対応状況と収集設定の永続化契約です。
nonisolated protocol VehiclePIDSettingRepository: Sendable {
    /// 責務: 車両の全PID設定を返します。
    func settings(for vehicleID: VehicleID) async throws -> [VehiclePIDSetting]
    /// 責務: 探索で確認した対応PIDを反映します。既存行の収集設定は変えず、未登録のPIDは収集有効で追加します。
    func mergeDiscovered(_ supported: Set<OBDPIDRequest>, for vehicleID: VehicleID, at date: Date) async throws
    /// 責務: 1つのPIDの収集有効・無効を切り替えます。
    func setCollectionEnabled(_ isEnabled: Bool, for request: OBDPIDRequest, vehicleID: VehicleID) async throws
}
