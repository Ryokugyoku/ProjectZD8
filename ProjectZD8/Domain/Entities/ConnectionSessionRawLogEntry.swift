import Foundation

/// 1件のOBD要求に対応する未デコード応答ログです。
struct ConnectionSessionRawLogEntry: Codable, Equatable, Sendable {
    /// セッション内で単調増加する記録順序です。
    let sequence: Int64
    /// 応答を観測した実時間です。
    let observedAt: Date
    /// 要求バッチ開始から応答群を受け取るまでの単調時間です。
    let batchElapsedNanoseconds: UInt64
    /// OBD Service番号です。
    let service: UInt8
    /// Service内PID番号です。
    let pid: UInt8
    /// 数値化や単位変換を適用していない応答データバイトです。
    let payload: [UInt8]

    /// 未デコード応答をセッション内の記録順序へ固定して生成します。
    ///
    /// 責務: 1件のRaw OBD応答を学習元として再現可能なセッションログへ変換します。
    /// - Parameters:
    ///   - sequence: セッション内で重複しない単調増加番号。
    ///   - observedAt: 応答を観測した実時間。
    ///   - batchElapsedNanoseconds: 要求バッチ開始から応答群受信までの単調時間。
    ///   - service: OBD Service番号。
    ///   - pid: Service内PID番号。
    ///   - payload: 未デコード応答データバイト。
    init(
        sequence: Int64,
        observedAt: Date,
        batchElapsedNanoseconds: UInt64,
        service: UInt8,
        pid: UInt8,
        payload: [UInt8]
    ) {
        self.sequence = sequence
        self.observedAt = observedAt
        self.batchElapsedNanoseconds = batchElapsedNanoseconds
        self.service = service
        self.pid = pid
        self.payload = payload
    }
}
