@testable import ProjectZD8

/// 観測VIN付きセッションの照会・紐付けの引数を記録し、固定結果または失敗を返すRepositoryのフェイクです。
final class ObservedVINConnectionSessionRepositorySpy: ObservedVINConnectionSessionRepository {
    /// 紐付け1回分の引数です。
    struct AssignCall: Equatable {
        /// 設定する車両です。
        let vehicle: ConnectionSessionVehicle
        /// 照合する観測VINです。
        let observedVIN: String
        /// 更新対象のアカウント識別子です。
        let accountIdentifier: String
    }

    /// 照会で返すセッションです。
    var unassignedResult: [ConnectionSession] = []
    /// 紐付けで返す更新件数です。
    var assignResult = 0
    /// 照会・紐付けで投げるエラーです。`nil` の場合は投げません。
    var failure: (any Error)?
    /// 照会に使われたアカウント識別子の記録です。
    private(set) var unassignedQueries: [String] = []
    /// 紐付けの引数の記録です。
    private(set) var assignCalls: [AssignCall] = []

    /// 照会を記録し、固定結果を返します。
    ///
    /// 責務: 照会引数を記録し、指定の失敗または固定結果を返します。
    /// - Parameter accountIdentifier: 照会対象のアカウント識別子。
    /// - Returns: `unassignedResult`。
    /// - Throws: `failure` を指定した場合はそのエラー。
    func unassignedSessionsWithObservedVIN(for accountIdentifier: String) throws -> [ConnectionSession] {
        unassignedQueries.append(accountIdentifier)
        if let failure { throw failure }
        return unassignedResult
    }

    /// 紐付けを記録し、固定件数を返します。
    ///
    /// 責務: 紐付け引数を記録し、指定の失敗または固定件数を返します。
    /// - Parameters:
    ///   - vehicle: 設定する車両。
    ///   - observedVIN: 照合する観測VIN。
    ///   - accountIdentifier: 更新対象のアカウント識別子。
    /// - Returns: `assignResult`。
    /// - Throws: `failure` を指定した場合はそのエラー。
    func assignVehicle(
        _ vehicle: ConnectionSessionVehicle,
        toUnassignedSessionsWithObservedVIN observedVIN: String,
        for accountIdentifier: String
    ) throws -> Int {
        assignCalls.append(AssignCall(vehicle: vehicle, observedVIN: observedVIN, accountIdentifier: accountIdentifier))
        if let failure { throw failure }
        return assignResult
    }
}
