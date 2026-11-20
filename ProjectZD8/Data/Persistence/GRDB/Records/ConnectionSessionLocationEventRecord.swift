import Foundation
import GRDB

/// GRDBへ保存する位置記録事象の永続化表現です。
nonisolated struct ConnectionSessionLocationEventRecord: Codable, FetchableRecord, PersistableRecord {
    /// 位置記録事象表名です。
    static let databaseTableName = "connection_session_location_events"

    /// 親接続セッションUUIDの文字列表現です。
    let sessionID: String
    /// セッション内の事象番号です。
    let eventOrdinal: Int64
    /// 事象が起きた実時間のmicrosecondです。
    let occurredAtMicroseconds: Int64
    /// 事象の種類のrawValueです。
    let kind: String

    /// Domainの事象をGRDB保存値へ変換します。
    ///
    /// 責務: 1件の位置記録事象を列指向の永続化表現へ変換します。
    /// - Parameters:
    ///   - kind: 事象の種類。
    ///   - ordinal: セッション内の事象番号。
    ///   - occurredAt: 事象が起きた実時間。
    ///   - sessionID: 親接続セッションID。
    /// - Throws: 時刻がInt64列へ表現できない場合は `ConnectionSessionRepositoryError.integrityConflict`。
    init(kind: ConnectionSessionLocationEventKind, ordinal: Int64, occurredAt: Date, sessionID: ConnectionSessionID) throws {
        self.sessionID = sessionID.rawValue.uuidString.lowercased()
        eventOrdinal = ordinal
        occurredAtMicroseconds = try ConnectionSessionMicrosecondTimestamp.microseconds(for: occurredAt)
        self.kind = kind.rawValue
    }

    /// GRDB列からDomainの位置記録事象を復元します。
    ///
    /// 責務: 1件の保存済み事象を範囲と種類を検証してDomainへ復元します。
    /// - Returns: 復元した事象。
    /// - Throws: 範囲外の番号や未知の種類は `ConnectionSessionRepositoryError.integrityConflict`。
    func makeDomainEvent() throws -> ConnectionSessionLocationEvent {
        guard let ordinal = Int(exactly: eventOrdinal), ordinal >= 0,
              let kind = ConnectionSessionLocationEventKind(rawValue: kind) else {
            throw ConnectionSessionRepositoryError.integrityConflict
        }
        return ConnectionSessionLocationEvent(
            ordinal: ordinal,
            occurredAt: ConnectionSessionMicrosecondTimestamp.date(fromMicroseconds: occurredAtMicroseconds),
            kind: kind
        )
    }
}
