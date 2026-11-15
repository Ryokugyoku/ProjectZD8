import Foundation

/// 応答駆動の取得ループが1周回(1 batch)の開始を記録するための確定済み入力です。
nonisolated struct LiveTelemetryAcquisitionRoundInput: Equatable, Sendable {
    /// 取得ループが所有する世代です。
    let generation: UInt
    /// セッション内で周回ごとに1ずつ増えるbatch番号です。
    let batchOrdinal: Int64
    /// polling policyが評価した周回番号です。
    let policyTick: UInt
    /// 周回の最初の要求を送る直前の実時間です。
    let startedAt: Date
    /// 今周回で送る順序付きService/PID要求です。
    let requests: [OBDPIDRequest]

    /// 1周回の識別子と要求列を固定します。
    ///
    /// 責務: 世代、batch番号、周回番号、開始時刻、要求列を1件の周回開始入力へまとめます。
    /// - Parameters:
    ///   - generation: 取得ループが所有する世代。
    ///   - batchOrdinal: セッション内で周回ごとに1ずつ増えるbatch番号。
    ///   - policyTick: polling policyが評価した周回番号。
    ///   - startedAt: 周回の最初の要求を送る直前の実時間。
    ///   - requests: 今周回で送る順序付きService/PID要求。
    init(
        generation: UInt,
        batchOrdinal: Int64,
        policyTick: UInt,
        startedAt: Date,
        requests: [OBDPIDRequest]
    ) {
        self.generation = generation
        self.batchOrdinal = batchOrdinal
        self.policyTick = policyTick
        self.startedAt = startedAt
        self.requests = requests
    }
}
