import Foundation
import GRDB

/// GRDBへ保存する取得の空白の永続化表現です。
nonisolated struct ConnectionSessionGapRecord: Codable, FetchableRecord, PersistableRecord {
    /// 欠損表名です。
    static let databaseTableName = "connection_session_gaps"

    /// 親接続セッションUUIDの文字列表現です。
    let sessionID: String
    /// セッション内の欠損番号です。
    let gapOrdinal: Int64
    /// 空白の直前に終わった区間の番号です。
    let precedingSegmentOrdinal: Int64
    /// 空白の直後に始まった区間の番号です。
    let followingSegmentOrdinal: Int64?
    /// 空白開始microsecondです。
    let startedAtMicroseconds: Int64
    /// 空白終了microsecondです。
    let endedAtMicroseconds: Int64?
    /// 欠損原因のrawValueです。
    let cause: String

    /// Domainの空白をGRDB保存値へ変換します。
    ///
    /// 責務: 1件の取得の空白を列指向の永続化表現へ変換します。
    /// - Parameters:
    ///   - gap: 保存する空白。
    ///   - sessionID: 親接続セッションID。
    /// - Throws: 時刻がInt64列へ表現できない場合は `ConnectionSessionRepositoryError.integrityConflict`。
    init(gap: ConnectionSessionGap, sessionID: ConnectionSessionID) throws {
        self.sessionID = sessionID.rawValue.uuidString.lowercased()
        gapOrdinal = Int64(gap.gapOrdinal)
        precedingSegmentOrdinal = Int64(gap.precedingSegmentOrdinal)
        followingSegmentOrdinal = gap.followingSegmentOrdinal.map(Int64.init)
        startedAtMicroseconds = try ConnectionSessionMicrosecondTimestamp.microseconds(for: gap.startedAt)
        endedAtMicroseconds = try gap.endedAt.map(ConnectionSessionMicrosecondTimestamp.microseconds)
        cause = gap.cause.rawValue
    }

    /// GRDB列からDomainの空白を復元します。
    ///
    /// 責務: 1件の保存済み空白を範囲と時間順を検証してDomainへ復元します。
    /// - Returns: 復元した空白。
    /// - Throws: 範囲外の値、未知の欠損原因、開始より前の終了時刻は
    ///   `ConnectionSessionRepositoryError.integrityConflict`。
    func makeDomainGap() throws -> ConnectionSessionGap {
        guard let ordinal = Int(exactly: gapOrdinal), ordinal >= 0,
              let preceding = Int(exactly: precedingSegmentOrdinal), preceding >= 0,
              let cause = ConnectionSessionGapCause(rawValue: cause),
              endedAtMicroseconds.map({ $0 >= startedAtMicroseconds }) ?? true else {
            throw ConnectionSessionRepositoryError.integrityConflict
        }
        var following: Int?
        if let followingSegmentOrdinal {
            guard let value = Int(exactly: followingSegmentOrdinal), value >= 0 else {
                throw ConnectionSessionRepositoryError.integrityConflict
            }
            following = value
        }
        return ConnectionSessionGap(
            gapOrdinal: ordinal,
            precedingSegmentOrdinal: preceding,
            followingSegmentOrdinal: following,
            startedAt: ConnectionSessionMicrosecondTimestamp.date(fromMicroseconds: startedAtMicroseconds),
            endedAt: endedAtMicroseconds.map(ConnectionSessionMicrosecondTimestamp.date),
            cause: cause
        )
    }
}
