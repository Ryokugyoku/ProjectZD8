import Foundation
import GRDB

/// GRDBへ保存する未デコードOBD応答の永続化表現です。
struct ConnectionSessionRawLogRecord: Codable, FetchableRecord, PersistableRecord {
    /// Rawログテーブル名です。
    static let databaseTableName = "connection_session_raw_logs"

    /// 親接続セッションUUIDの文字列表現です。
    let sessionID: String
    /// セッション内で単調増加する記録順序です。
    let sequence: Int64
    /// 応答を観測した実時間です。
    let observedAt: Date
    /// 要求バッチ開始から応答群受信までの単調時間です。
    let batchElapsedNanoseconds: Int64
    /// OBD Service番号です。
    let service: Int
    /// Service内PID番号です。
    let pid: Int
    /// 数値化前の応答データバイトです。
    let payload: Data
    /// 観測時点の単調時計ナノ秒値です。記録していない既存行では `nil` です。
    let monotonicNanoseconds: Int64?
    /// 所属する連続取得区間の番号です。記録していない既存行では `nil` です。
    let segmentOrdinal: Int64?

    /// Domain RawログをGRDB保存値へ変換します。
    ///
    /// 責務: 1件の未デコードOBD応答を列指向の永続化表現へ変換します。
    /// - Parameters:
    ///   - entry: 保存する順序付きRawログ。
    ///   - sessionID: 親接続セッションID。
    init(entry: ConnectionSessionRawLogEntry, sessionID: ConnectionSessionID) {
        self.sessionID = sessionID.rawValue.uuidString.lowercased()
        sequence = entry.sequence
        observedAt = entry.observedAt
        batchElapsedNanoseconds = Int64(clamping: entry.batchElapsedNanoseconds)
        service = Int(entry.service)
        pid = Int(entry.pid)
        payload = Data(entry.payload)
        monotonicNanoseconds = entry.monotonicNanoseconds.map { Int64(clamping: $0) }
        segmentOrdinal = entry.segmentOrdinal.map(Int64.init)
    }

    /// GRDB列からDomain Rawログを復元します。
    ///
    /// 責務: 1件の検証済みGRDB RawログをDomain転送表現へ復元します。
    /// - Returns: Service、PID、経過時間、単調時計値、区間番号が有効範囲の場合のRawログ。
    func makeDomainEntry() -> ConnectionSessionRawLogEntry? {
        guard batchElapsedNanoseconds >= 0,
              let service = UInt8(exactly: service),
              let pid = UInt8(exactly: pid),
              let monotonic = restoredMonotonicNanoseconds,
              let segment = restoredSegmentOrdinal else {
            return nil
        }
        return ConnectionSessionRawLogEntry(
            sequence: sequence,
            observedAt: observedAt,
            batchElapsedNanoseconds: UInt64(batchElapsedNanoseconds),
            service: service,
            pid: pid,
            payload: [UInt8](payload),
            monotonicNanoseconds: monotonic,
            segmentOrdinal: segment
        )
    }

    /// 保存済み単調時計値をDomainの値へ復元します。
    ///
    /// 責務: NULLは未記録として保持し、負数は復元不能として区別します。
    /// - Returns: 未記録なら `.some(nil)`、有効値なら `.some(値)`、負数なら `nil`。
    private var restoredMonotonicNanoseconds: UInt64?? {
        guard let monotonicNanoseconds else { return .some(nil) }
        guard let value = UInt64(exactly: monotonicNanoseconds) else { return nil }
        return .some(value)
    }

    /// 保存済み区間番号をDomainの値へ復元します。
    ///
    /// 責務: NULLは未記録として保持し、負数またはInt範囲外は復元不能として区別します。
    /// - Returns: 未記録なら `.some(nil)`、有効値なら `.some(値)`、範囲外なら `nil`。
    private var restoredSegmentOrdinal: Int?? {
        guard let segmentOrdinal else { return .some(nil) }
        guard segmentOrdinal >= 0, let value = Int(exactly: segmentOrdinal) else { return nil }
        return .some(value)
    }
}
