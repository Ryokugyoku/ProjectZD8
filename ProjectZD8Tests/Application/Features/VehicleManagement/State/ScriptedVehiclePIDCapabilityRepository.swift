import Foundation
@testable import ProjectZD8

/// 車両ごとの対応PIDを返し、読込・保存の失敗を指定でき、収集選択の更新を記録する対応PID Repository の fake です。
final class ScriptedVehiclePIDCapabilityRepository: VehiclePIDCapabilityRepository, @unchecked Sendable {
    /// 読込や保存を失敗させるときに投げるエラーです。
    struct Failure: Error {}

    /// 記録した1件の収集選択の更新です。
    struct Change: Equatable {
        /// 新しい収集有効状態です。
        let isEnabled: Bool
        /// 更新対象のService/PIDです。
        let request: OBDPIDRequest
        /// 更新対象の車両IDです。
        let vehicleID: VehicleID
    }

    /// 車両IDごとの対応PIDです。未設定の車両は空を返します。
    var capabilitiesByVehicle: [VehicleID: [VehiclePIDCapability]]

    /// 読込を失敗させる車両IDです。
    var failingReadVehicleIDs: Set<VehicleID> = []

    /// `true` の間、収集選択の保存は失敗します。
    var failsSave = false

    /// 保存に成功した収集選択の更新を順に記録します。
    private(set) var changes: [Change] = []

    /// 車両ごとの対応PIDを固定して生成します。
    ///
    /// 責務: 車両IDごとの対応PIDを保持する fake を作ります。
    /// - Parameter capabilitiesByVehicle: 車両IDごとの対応PID。
    init(capabilitiesByVehicle: [VehicleID: [VehiclePIDCapability]] = [:]) {
        self.capabilitiesByVehicle = capabilitiesByVehicle
    }

    /// 指定車両の対応PIDを返します。
    ///
    /// 責務: 失敗指定の車両なら throw し、そうでなければその車両の対応PIDを返します。
    /// - Parameter vehicleID: 照会する車両ID。
    /// - Returns: その車両の対応PID。未設定なら空配列。
    /// - Throws: 失敗指定の車両では `Failure`。
    func capabilities(for vehicleID: VehicleID) throws -> [VehiclePIDCapability] {
        if failingReadVehicleIDs.contains(vehicleID) { throw Failure() }
        return capabilitiesByVehicle[vehicleID] ?? []
    }

    /// 初回登録を受け付けます。
    ///
    /// 責務: テストで使わない初回登録を変更なしで完了します。
    /// - Parameters:
    ///   - capabilities: 使わない対応PID。
    ///   - vehicleID: 使わない車両ID。
    func insertInitial(_ capabilities: [VehiclePIDCapability], for vehicleID: VehicleID) throws {}

    /// 追加登録を受け付けます。
    ///
    /// 責務: テストで使わない追加登録を変更なしで完了します。
    /// - Parameters:
    ///   - capabilities: 使わない対応PID。
    ///   - vehicleID: 使わない車両ID。
    func mergeDiscovered(_ capabilities: [VehiclePIDCapability], for vehicleID: VehicleID) throws {}

    /// 収集選択の更新を記録します。
    ///
    /// 責務: 失敗指定なら throw し、そうでなければ更新1件を記録します。
    /// - Parameters:
    ///   - isEnabled: 新しい収集有効状態。
    ///   - request: 更新するService/PID。
    ///   - vehicleID: 更新対象の車両ID。
    /// - Throws: `failsSave` が `true` の場合は `Failure`。
    func setCollectionEnabled(_ isEnabled: Bool, for request: OBDPIDRequest, vehicleID: VehicleID) throws {
        if failsSave { throw Failure() }
        changes.append(Change(isEnabled: isEnabled, request: request, vehicleID: vehicleID))
    }
}
