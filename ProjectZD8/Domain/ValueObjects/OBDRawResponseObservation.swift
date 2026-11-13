import Foundation

/// セッション割当て前にApplicationが受け取る未デコードOBD応答です。
nonisolated struct OBDRawResponseObservation: Equatable, Sendable {
    /// 応答を観測した実時間です。
    let observedAt: Date
    /// 要求バッチ開始から応答群受信までの単調時間です。
    let batchElapsedNanoseconds: UInt64
    /// 応答対象のOBD要求です。
    let request: OBDPIDRequest
    /// 数値化前の応答データバイトです。
    let payload: [UInt8]

    /// 取得境界のRaw応答をセッション未割当て観測として生成します。
    ///
    /// 責務: 1件のOBD応答と観測時刻をLoggingへ渡せる不変値へまとめます。
    /// - Parameters:
    ///   - observedAt: 応答を観測した実時間。
    ///   - batchElapsedNanoseconds: 要求バッチ開始から応答群受信までの単調時間。
    ///   - request: 応答対象のService/PID要求。
    ///   - payload: 未デコード応答データバイト。
    init(
        observedAt: Date,
        batchElapsedNanoseconds: UInt64,
        request: OBDPIDRequest,
        payload: [UInt8]
    ) {
        self.observedAt = observedAt
        self.batchElapsedNanoseconds = batchElapsedNanoseconds
        self.request = request
        self.payload = payload
    }
}
