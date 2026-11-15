@testable import ProjectZD8

/// 観測VINからの車両登録テストで、空の一覧を返し保存要求を記録する車両 Repository の fake です。
@MainActor
final class ObservedVINRegistrationVehicleRepositoryFake: VehicleRepository {
    /// 保存要求として受け取った車両です(受信順)。
    private(set) var savedVehicles: [VehicleProfile] = []

    /// 空の登録車両一覧を返します。
    ///
    /// 責務: 指定アカウントの車両一覧を空として返します。
    /// - Parameter accountIdentifier: テスト用アカウント識別子。
    /// - Returns: 空の車両一覧。
    func loadVehicles(for accountIdentifier: String) async throws -> [VehicleProfile] { [] }

    /// 保存要求を記録します。
    ///
    /// 責務: 保存対象の車両を記録して成功します。
    /// - Parameters:
    ///   - vehicle: 保存対象の車両。
    ///   - accountIdentifier: テスト用アカウント識別子。
    func saveVehicle(_ vehicle: VehicleProfile, for accountIdentifier: String) async throws {
        savedVehicles.append(vehicle)
    }

    /// 削除要求を受理します。
    ///
    /// 責務: このテストでは使わない削除要求を副作用なしで受理します。
    /// - Parameters:
    ///   - id: 削除対象の車両ID。
    ///   - accountIdentifier: テスト用アカウント識別子。
    func deleteVehicle(id: VehicleID, for accountIdentifier: String) async throws {}
}
