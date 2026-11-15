import Foundation
@testable import ProjectZD8

/// アカウントごとに車両一覧を持ち、読込の呼び出しを記録し、指定時だけ読込を失敗させる車両 Repository の fake です。
@MainActor
final class AccountScopedVehicleRepositoryFake: VehicleRepository {
    /// アカウント識別子ごとの登録済み車両です。
    var vehiclesByAccount: [String: [VehicleProfile]] = [:]

    /// 設定されている場合、読込はこのエラーで失敗します。
    var loadFailure: (any Error)?

    /// 設定されている場合、保存はこのエラーで失敗します。
    var saveFailure: (any Error)?

    /// 読込を要求されたアカウント識別子を順に記録します。
    private(set) var loadedAccounts: [String] = []

    /// 指定アカウントの車両を返します。
    ///
    /// 責務: 呼び出しを記録し、失敗指定があれば throw し、無ければそのアカウントの車両だけを返します。
    /// - Parameter accountIdentifier: 読み込むアカウント識別子。
    /// - Returns: そのアカウントの登録済み車両。未設定なら空配列。
    /// - Throws: `loadFailure` が設定されている場合はそのエラー。
    func loadVehicles(for accountIdentifier: String) async throws -> [VehicleProfile] {
        loadedAccounts.append(accountIdentifier)
        if let loadFailure { throw loadFailure }
        return vehiclesByAccount[accountIdentifier] ?? []
    }

    /// 車両を指定アカウントの一覧へ追加または置き換えます。
    ///
    /// 責務: 失敗指定があれば throw し、無ければ同じIDの置き換えか末尾への追加として反映します。
    /// - Parameters:
    ///   - vehicle: 保存する車両。
    ///   - accountIdentifier: 保存先のアカウント識別子。
    /// - Throws: `saveFailure` が設定されている場合はそのエラー。
    func saveVehicle(_ vehicle: VehicleProfile, for accountIdentifier: String) async throws {
        if let saveFailure { throw saveFailure }
        var vehicles = vehiclesByAccount[accountIdentifier] ?? []
        vehicles.removeAll { $0.id == vehicle.id }
        vehicles.append(vehicle)
        vehiclesByAccount[accountIdentifier] = vehicles
    }

    /// 指定IDの車両を一覧から外します。
    ///
    /// 責務: 削除要求を指定アカウントの一覧へ反映します。
    /// - Parameters:
    ///   - id: 削除する車両ID。
    ///   - accountIdentifier: 対象のアカウント識別子。
    func deleteVehicle(id: VehicleID, for accountIdentifier: String) async throws {
        vehiclesByAccount[accountIdentifier]?.removeAll { $0.id == id }
    }
}
