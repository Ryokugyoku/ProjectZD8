import Foundation
import GRDB

/// GRDBへ保存する連続取得区間の永続化表現です。
nonisolated struct ConnectionSessionSegmentRecord: Codable, FetchableRecord, PersistableRecord {
    /// セグメント表名です。
    static let databaseTableName = "connection_session_segments"

    /// 親接続セッションUUIDの文字列表現です。
    let sessionID: String
    /// セッション内の区間番号です。
    let segmentOrdinal: Int64
    /// 区間開始理由のrawValueです。
    let startReason: String
    /// 取得方式のrawValueです。
    let acquisitionMode: String
    /// 区間開始microsecondです。
    let startedAtMicroseconds: Int64
    /// 開始時に採取した単調時計のナノ秒値です。
    let monotonicAnchorNanoseconds: Int64
    /// 区間の最初の記録順序です。
    let firstSequence: Int64
    /// 区間終了microsecondです。
    let endedAtMicroseconds: Int64?
    /// 区間終了理由のrawValueです。
    let endReason: String?
    /// 区間の最後の記録順序です。
    let lastSequence: Int64?

    /// Domain区間をGRDB保存値へ変換します。
    ///
    /// 責務: 1件の連続取得区間を列指向の永続化表現へ変換します。
    /// - Parameters:
    ///   - segment: 保存する連続取得区間。
    ///   - sessionID: 親接続セッションID。
    /// - Throws: 時刻または単調時計値がInt64列へ表現できない場合は
    ///   `ConnectionSessionRepositoryError.integrityConflict`。
    init(segment: ConnectionSessionSegment, sessionID: ConnectionSessionID) throws {
        guard let anchor = Int64(exactly: segment.monotonicAnchorNanoseconds) else {
            throw ConnectionSessionRepositoryError.integrityConflict
        }
        self.sessionID = sessionID.rawValue.uuidString.lowercased()
        segmentOrdinal = Int64(segment.segmentOrdinal)
        startReason = segment.startReason.rawValue
        acquisitionMode = segment.acquisitionMode.rawValue
        startedAtMicroseconds = try ConnectionSessionMicrosecondTimestamp.microseconds(for: segment.startedAt)
        monotonicAnchorNanoseconds = anchor
        firstSequence = segment.firstSequence
        endedAtMicroseconds = try segment.endedAt.map(ConnectionSessionMicrosecondTimestamp.microseconds)
        endReason = segment.endReason?.rawValue
        lastSequence = segment.lastSequence
    }

    /// GRDB列からDomain区間を復元します。
    ///
    /// 責務: 1件の保存済み区間を範囲と終了情報の組み合わせを検証してDomainへ復元します。
    /// - Returns: 復元した連続取得区間。
    /// - Throws: 範囲外の値、未知の列挙値、終了情報の不整合は
    ///   `ConnectionSessionRepositoryError.integrityConflict`。
    func makeDomainSegment() throws -> ConnectionSessionSegment {
        guard let ordinal = Int(exactly: segmentOrdinal), ordinal >= 0,
              let startReason = ConnectionSessionSegmentStartReason(rawValue: startReason),
              let acquisitionMode = ConnectionSessionAcquisitionMode(rawValue: acquisitionMode),
              let anchor = UInt64(exactly: monotonicAnchorNanoseconds),
              firstSequence >= 0,
              hasConsistentTermination else {
            throw ConnectionSessionRepositoryError.integrityConflict
        }
        return ConnectionSessionSegment(
            segmentOrdinal: ordinal,
            startReason: startReason,
            acquisitionMode: acquisitionMode,
            startedAt: ConnectionSessionMicrosecondTimestamp.date(fromMicroseconds: startedAtMicroseconds),
            monotonicAnchorNanoseconds: anchor,
            firstSequence: firstSequence,
            endedAt: endedAtMicroseconds.map(ConnectionSessionMicrosecondTimestamp.date),
            endReason: endReason.flatMap(ConnectionSessionSegmentEndReason.init),
            lastSequence: lastSequence
        )
    }

    /// 終了時刻、終了理由、最終記録順序の組み合わせがスキーマ制約を満たすかを返します。
    ///
    /// 責務: 未終了なら3列すべてNULL、終了済みなら既知の理由と開始以降の時刻を持つことを判定します。
    private var hasConsistentTermination: Bool {
        if let lastSequence, lastSequence < firstSequence {
            return false
        }
        guard let endedAtMicroseconds else {
            return endReason == nil && lastSequence == nil
        }
        guard let endReason, ConnectionSessionSegmentEndReason(rawValue: endReason) != nil else {
            return false
        }
        return endedAtMicroseconds >= startedAtMicroseconds
    }
}
