import Foundation

/// 車両ごとの、1つのPIDに対する対応状況と収集設定です。
nonisolated struct VehiclePIDSetting: Equatable, Sendable {
    let vehicleID: VehicleID
    let request: OBDPIDRequest
    /// 車両がこのPIDへ応答すると確認できたかどうかです。
    var isSupported: Bool
    /// ユーザーがこのPIDの収集を有効にしているかどうかです。
    var isCollectionEnabled: Bool
    /// 対応状況を最後に確認した日時です。
    var discoveredAt: Date

    /// PID設定を生成します。
    ///
    /// 責務: 1車両・1PIDの対応状況と収集設定をまとめます。
    init(vehicleID: VehicleID, request: OBDPIDRequest, isSupported: Bool, isCollectionEnabled: Bool = true, discoveredAt: Date) {
        self.vehicleID = vehicleID
        self.request = request
        self.isSupported = isSupported
        self.isCollectionEnabled = isCollectionEnabled
        self.discoveredAt = discoveredAt
    }
}
