import Foundation
@testable import ProjectZD8

/// 車両不明ログの照会・紐付けをメモリ上の一覧で再現し、引数を記録するRepositoryのフェイクです。
///
/// 紐付けは指定IDのうち一覧にあるものを一覧から外し、その件数を返します(保存先の「対象の行だけ更新」の契約を写します)。
final class VehicleUnknownConnectionSessionRepositoryFake: VehicleUnknownConnectionSessionRepository {
    /// 紐付け1回分の引数です。
    struct AssignCall: Equatable {
        /// 設定する車両です。
        let vehicle: ConnectionSessionVehicle
        /// 紐付けるセッションのIDです(呼び出し時の並び)。
        let sessionIDs: [ConnectionSessionID]
        /// 更新対象のアカウント識別子です。
        let accountIdentifier: String
    }

    /// アカウントごとの車両不明ログです(照会はこの並びのまま返します)。
    var sessionsByAccount: [String: [ConnectionSession]] = [:]
    /// 照会で投げるエラーです。`nil` の場合は投げません。
    var loadFailure: (any Error)?
    /// 紐付けで投げるエラーです。`nil` の場合は投げません。
    var assignFailure: (any Error)?
    /// 照会に使われたアカウント識別子の記録です。
    private(set) var loadQueries: [String] = []
    /// 紐付けの引数の記録です。
    private(set) var assignCalls: [AssignCall] = []

    /// 照会を記録し、アカウントの一覧を返します。
    ///
    /// 責務: 照会引数を記録し、指定の失敗またはアカウントの一覧を返します。
    /// - Parameter accountIdentifier: 照会対象のアカウント識別子。
    /// - Returns: アカウントの車両不明ログ。
    /// - Throws: `loadFailure` を指定した場合はそのエラー。
    func vehicleUnknownSessions(for accountIdentifier: String) throws -> [ConnectionSession] {
        loadQueries.append(accountIdentifier)
        if let loadFailure { throw loadFailure }
        return sessionsByAccount[accountIdentifier] ?? []
    }

    /// 紐付けを記録し、一覧にあるIDだけを一覧から外して件数を返します。
    ///
    /// 責務: 紐付け引数を記録し、指定の失敗または更新件数を返します。
    /// - Parameters:
    ///   - vehicle: 設定する車両。
    ///   - sessionIDs: 紐付けるセッションのID。
    ///   - accountIdentifier: 更新対象のアカウント識別子。
    /// - Returns: 一覧から外した件数。
    /// - Throws: `assignFailure` を指定した場合はそのエラー。
    func assignVehicle(
        _ vehicle: ConnectionSessionVehicle,
        toVehicleUnknownSessions sessionIDs: [ConnectionSessionID],
        for accountIdentifier: String
    ) throws -> Int {
        assignCalls.append(AssignCall(vehicle: vehicle, sessionIDs: sessionIDs, accountIdentifier: accountIdentifier))
        if let assignFailure { throw assignFailure }
        let targets = Set(sessionIDs)
        let before = sessionsByAccount[accountIdentifier] ?? []
        let remaining = before.filter { !targets.contains($0.id) }
        sessionsByAccount[accountIdentifier] = remaining
        return before.count - remaining.count
    }
}
