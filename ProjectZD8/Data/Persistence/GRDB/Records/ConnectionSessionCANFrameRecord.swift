import Foundation
import GRDB

/// GRDBへ保存する受信CANフレームの永続化表現です。
nonisolated struct ConnectionSessionCANFrameRecord: Codable, FetchableRecord, PersistableRecord {
    /// CANフレーム表名です。
    static let databaseTableName = "connection_session_can_frames"
    /// 29bit拡張識別子の最大値です。
    static let maximumCANIdentifier: Int64 = 0x1FFF_FFFF
    /// CAN FDのpayload最大バイト数です。
    static let maximumPayloadByteCount = 64

    /// 親接続セッションUUIDの文字列表現です。
    let sessionID: String
    /// 呼び出し側が採番したセッション内の記録順序です。
    let sequence: Int64
    /// フレームを受信した区間の番号です。
    let segmentOrdinal: Int64
    /// 受信microsecondです。
    let receivedAtMicroseconds: Int64
    /// 受信時に採取した単調時計のナノ秒値です。
    let monotonicNanoseconds: Int64
    /// CAN識別子です。
    let canIdentifier: Int64
    /// 未デコードのデータバイトです。
    let payload: Data

    /// DomainのCANフレームをGRDB保存値へ変換します。
    ///
    /// 責務: 1件の受信CANフレームを列指向の永続化表現へ変換します。
    /// - Parameters:
    ///   - frame: 保存する受信CANフレーム。
    ///   - sessionID: 親接続セッションID。
    /// - Throws: 時刻または単調時計値がInt64列へ表現できない場合は
    ///   `ConnectionSessionRepositoryError.integrityConflict`。
    init(frame: CANFrameObservation, sessionID: ConnectionSessionID) throws {
        guard let monotonic = Int64(exactly: frame.monotonicNanoseconds) else {
            throw ConnectionSessionRepositoryError.integrityConflict
        }
        self.sessionID = sessionID.rawValue.uuidString.lowercased()
        sequence = frame.sequence
        segmentOrdinal = Int64(frame.segmentOrdinal)
        receivedAtMicroseconds = try ConnectionSessionMicrosecondTimestamp.microseconds(for: frame.receivedAt)
        monotonicNanoseconds = monotonic
        canIdentifier = Int64(frame.canIdentifier)
        payload = Data(frame.payload)
    }

    /// GRDB列からDomainのCANフレームを復元します。
    ///
    /// 責務: 1件の保存済みCANフレームを識別子とpayload長の範囲を検証してDomainへ復元します。
    /// - Returns: 復元した受信CANフレーム。
    /// - Throws: 範囲外の値は `ConnectionSessionRepositoryError.integrityConflict`。
    func makeDomainFrame() throws -> CANFrameObservation {
        guard sequence >= 0,
              let ordinal = Int(exactly: segmentOrdinal), ordinal >= 0,
              let monotonic = UInt64(exactly: monotonicNanoseconds),
              (0...Self.maximumCANIdentifier).contains(canIdentifier),
              let identifier = UInt32(exactly: canIdentifier),
              payload.count <= Self.maximumPayloadByteCount else {
            throw ConnectionSessionRepositoryError.integrityConflict
        }
        return CANFrameObservation(
            sequence: sequence,
            segmentOrdinal: ordinal,
            receivedAt: ConnectionSessionMicrosecondTimestamp.date(fromMicroseconds: receivedAtMicroseconds),
            monotonicNanoseconds: monotonic,
            canIdentifier: identifier,
            payload: [UInt8](payload)
        )
    }
}
