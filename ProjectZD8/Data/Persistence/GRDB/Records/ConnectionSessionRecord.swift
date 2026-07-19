import Foundation
import GRDB

/// GRDBへ保存する接続セッションの永続化表現です。
struct ConnectionSessionRecord: Codable, FetchableRecord, PersistableRecord {
    /// 接続セッションテーブル名です。
    static let databaseTableName = "connection_sessions"

    /// セッションUUIDの文字列表現です。
    let id: String
    /// Appleアカウント識別子です。
    let accountIdentifier: String
    /// 開始日時です。
    let startedAt: Date
    /// 終了日時です。
    let endedAt: Date?
    /// 終了原因の安定文字列表現です。
    let endReason: String?
    /// 関連付けた登録車両UUIDの文字列表現です。
    let vehicleID: String?
    /// 接続時点の車両名称です。
    let vehicleName: String?
    /// 接続時点の車両代表識別値です。
    let vehicleDisplayIdentifier: String?
    /// セッション内で最初に取得した累積走行距離です。
    let startingOdometerKilometers: Double?
    /// セッション内で最後に取得した累積走行距離です。
    let endingOdometerKilometers: Double?

    /// DomainセッションをGRDB保存値へ変換します。
    ///
    /// 責務: 1件のDomain接続セッションを列指向の永続化表現へ変換します。
    /// - Parameter session: 永続化するDomainセッション。
    init(session: ConnectionSession) {
        id = session.id.rawValue.uuidString.lowercased()
        accountIdentifier = session.accountIdentifier
        startedAt = session.startedAt
        endedAt = session.endedAt
        endReason = session.endReason?.rawValue
        vehicleID = session.vehicle?.id.rawValue.uuidString.lowercased()
        vehicleName = session.vehicle?.name
        vehicleDisplayIdentifier = session.vehicle?.displayIdentifier
        startingOdometerKilometers = session.startingOdometerKilometers
        endingOdometerKilometers = session.endingOdometerKilometers
    }

    /// 永続化済み列からDomainセッションを復元します。
    ///
    /// 責務: 1件の検証済みGRDBレコードをDomain接続セッションへ復元します。
    /// - Returns: 復元できた接続セッション。不正な識別値または終了原因の場合は `nil`。
    func makeDomainSession() -> ConnectionSession? {
        guard let sessionUUID = UUID(uuidString: id) else { return nil }
        let reason: ConnectionSessionEndReason?
        if let endReason {
            guard let decoded = ConnectionSessionEndReason(rawValue: endReason) else { return nil }
            reason = decoded
        } else {
            reason = nil
        }
        let vehicle: ConnectionSessionVehicle?
        if let vehicleID, let vehicleName, let vehicleDisplayIdentifier,
           let vehicleUUID = UUID(uuidString: vehicleID) {
            vehicle = ConnectionSessionVehicle(
                id: VehicleID(rawValue: vehicleUUID),
                name: vehicleName,
                displayIdentifier: vehicleDisplayIdentifier
            )
        } else {
            vehicle = nil
        }
        var session = ConnectionSession(
            id: ConnectionSessionID(rawValue: sessionUUID),
            accountIdentifier: accountIdentifier,
            startedAt: startedAt,
            vehicle: vehicle
        )
        session.endedAt = endedAt
        session.endReason = reason
        session.startingOdometerKilometers = startingOdometerKilometers
        session.endingOdometerKilometers = endingOdometerKilometers
        return session
    }
}
