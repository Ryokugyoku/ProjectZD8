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
    }

    /// GRDB列からDomain Rawログを復元します。
    ///
    /// 責務: 1件の検証済みGRDB RawログをDomain転送表現へ復元します。
    /// - Returns: Service、PID、経過時間が有効範囲の場合のRawログ。
    func makeDomainEntry() -> ConnectionSessionRawLogEntry? {
        guard batchElapsedNanoseconds >= 0,
              let service = UInt8(exactly: service),
              let pid = UInt8(exactly: pid) else {
            return nil
        }
        return ConnectionSessionRawLogEntry(
            sequence: sequence,
            observedAt: observedAt,
            batchElapsedNanoseconds: UInt64(batchElapsedNanoseconds),
            service: service,
            pid: pid,
            payload: [UInt8](payload)
        )
    }
}
