import Foundation

/// 途絶から復帰したときに、欠損を挟んで次の連続取得区間を開くための入力です。
nonisolated struct LiveTelemetryAcquisitionSegmentResumption: Equatable, Sendable {
    /// 取得ループが所有する世代です。
    let generation: UInt
    /// 次の区間が始まった直接原因です。
    let startReason: ConnectionSessionSegmentStartReason
    /// 区間の間の欠損の原因です。
    let gapCause: ConnectionSessionGapCause
    /// 欠損が始まった実時間(最後に正応答を受信した時刻)です。
    let gapStartedAt: Date

    /// 復帰時の区間切替入力を固定します。
    ///
    /// 責務: 世代、開始理由、欠損の原因と開始時刻を1件の入力へまとめます。
    /// - Parameters:
    ///   - generation: 取得ループが所有する世代。
    ///   - startReason: 次の区間が始まった直接原因。
    ///   - gapCause: 区間の間の欠損の原因。
    ///   - gapStartedAt: 欠損が始まった実時間。
    init(
        generation: UInt,
        startReason: ConnectionSessionSegmentStartReason,
        gapCause: ConnectionSessionGapCause,
        gapStartedAt: Date
    ) {
        self.generation = generation
        self.startReason = startReason
        self.gapCause = gapCause
        self.gapStartedAt = gapStartedAt
    }
}
