import Foundation

/// 保存待ちバッファ内の、連番を割り当てる前の未デコード応答です。
nonisolated struct AcquisitionBufferedRaw: Equatable, Sendable {
    /// 応答を観測した実時間です。
    let observedAt: Date
    /// 応答を観測した時点の単調時計のナノ秒値です。
    let monotonicNanoseconds: UInt64
    /// 応答が属する連続取得区間の番号です。
    let segmentOrdinal: Int
    /// 要求送信から応答受信までの単調時間です。
    let elapsedNanoseconds: UInt64
    /// 応答したService/PID要求です。
    let request: OBDPIDRequest
    /// 未デコード応答データバイトです。
    let payload: [UInt8]

    /// 受信時点の時刻と区間を付けて応答を保持します。
    ///
    /// 責務: 1件の応答を連番割当前の保存待ち状態へ固定します。
    /// - Parameters:
    ///   - observedAt: 応答を観測した実時間。
    ///   - monotonicNanoseconds: 観測時点の単調時計ナノ秒値。
    ///   - segmentOrdinal: 所属する連続取得区間の番号。
    ///   - elapsedNanoseconds: 要求送信から応答受信までの単調時間。
    ///   - request: 応答したService/PID要求。
    ///   - payload: 未デコード応答データバイト。
    init(
        observedAt: Date,
        monotonicNanoseconds: UInt64,
        segmentOrdinal: Int,
        elapsedNanoseconds: UInt64,
        request: OBDPIDRequest,
        payload: [UInt8]
    ) {
        self.observedAt = observedAt
        self.monotonicNanoseconds = monotonicNanoseconds
        self.segmentOrdinal = segmentOrdinal
        self.elapsedNanoseconds = elapsedNanoseconds
        self.request = request
        self.payload = payload
    }

    /// 連番を割り当てて保存用のRaw entryへ変換します。
    ///
    /// 責務: 保存待ちの応答を採番済みRaw entryへ変換します。
    /// - Parameter sequence: セッション内で割り当てる記録順序。
    /// - Returns: 単調時計と区間番号を持つRaw entry。
    func entry(sequence: Int64) -> ConnectionSessionRawLogEntry {
        ConnectionSessionRawLogEntry(
            sequence: sequence,
            observedAt: observedAt,
            batchElapsedNanoseconds: elapsedNanoseconds,
            service: request.service,
            pid: request.pid,
            payload: payload,
            monotonicNanoseconds: monotonicNanoseconds,
            segmentOrdinal: segmentOrdinal
        )
    }
}
