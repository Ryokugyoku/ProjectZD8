import Foundation

/// 1台の車両で応答対応が確認されたService 01 PIDの収集設定です。
struct VehiclePIDCapability: Equatable, Identifiable, Sendable {
    /// 対応PIDレコードの安定複合識別子です。
    struct ID: Equatable, Hashable, Sendable {
        /// アプリ内の車両識別子です。
        let vehicleID: VehicleID
        /// OBD要求のService/PID識別子です。
        let request: OBDPIDRequest
    }

    /// 対応PIDレコードの安定複合識別子です。
    let id: ID
    /// 継続収集対象としてユーザーが選択しているかを示します。
    var isCollectionEnabled: Bool
    /// 対応ビットマップを最後に確認した日時です。
    let discoveredAt: Date

    /// 車両別の対応PIDと収集選択を生成します。
    ///
    /// 責務: 1台の車両と1件の対応PIDを収集選択および確認日時へ固定します。
    /// - Parameters:
    ///   - vehicleID: アプリ内の車両識別子。
    ///   - request: 対応が確認されたService/PID。
    ///   - isCollectionEnabled: 継続収集対象かどうか。
    ///   - discoveredAt: 対応確認日時。
    init(vehicleID: VehicleID, request: OBDPIDRequest, isCollectionEnabled: Bool, discoveredAt: Date) {
        id = ID(vehicleID: vehicleID, request: request)
        self.isCollectionEnabled = isCollectionEnabled
        self.discoveredAt = discoveredAt
    }
}
