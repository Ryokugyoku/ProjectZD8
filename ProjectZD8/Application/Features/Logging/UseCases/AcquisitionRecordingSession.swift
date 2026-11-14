import Foundation

/// 記録を受け付け中の1世代について、保存先の識別子と区間・欠損・commitの進行状態を保持します。
nonisolated struct AcquisitionRecordingSession: Equatable, Sendable {
    /// 記録先の接続セッションです。
    let sessionID: ConnectionSessionID
    /// 記録を受け付ける取得世代です。
    let generation: UInt
    /// manifestの要求順におけるService/PIDごとの位置です。
    let manifestOrdinalByRequest: [OBDPIDRequest: Int]
    /// 取得ループのbatch番号へ足して保存上のbatch番号にする値です。プロセス復帰後の続きで0以外になります。
    let batchOrdinalBase: Int64
    /// 現在(または直前)の連続取得区間の番号です。
    private(set) var segmentOrdinal: Int
    /// 現在の区間の最初の行へ割り当てる記録順序です。
    private(set) var segmentFirstSequence: Int64
    /// 現在の区間を開始した実時間です。
    private(set) var segmentStartedAt: Date
    /// 現在の区間が開いているかどうかです。途絶から復帰するまでの間は `false` です。
    private(set) var isSegmentOpen: Bool
    /// 次に記録する欠損の番号です。
    private(set) var nextGapOrdinal: Int
    /// 直近にcommitを試みた時点の単調時計の値です。区間開始時はその時点の値です。
    private(set) var lastCommitAttemptNanoseconds: UInt64
    /// 現在の区間で直近に付けた単調時計の値です。
    private(set) var lastStampedNanoseconds: UInt64

    /// 区間を開始した時点の記録状態を生成します。
    ///
    /// 責務: 記録先、manifest位置、区間、次の欠損番号、単調時計の起点を固定します。
    /// - Parameters:
    ///   - sessionID: 記録先の接続セッション。
    ///   - generation: 記録を受け付ける取得世代。
    ///   - orderedRequests: manifestの要求順。
    ///   - segmentOrdinal: 現在の連続取得区間の番号。
    ///   - segmentFirstSequence: 現在の区間の最初の行へ割り当てる記録順序。
    ///   - segmentStartedAt: 現在の区間を開始した実時間。
    ///   - nextGapOrdinal: 次に記録する欠損の番号。
    ///   - anchorNanoseconds: 区間を開始した時点の単調時計の値。
    ///   - batchOrdinalBase: 取得ループのbatch番号へ足す値。
    init(
        sessionID: ConnectionSessionID,
        generation: UInt,
        orderedRequests: [OBDPIDRequest],
        segmentOrdinal: Int,
        segmentFirstSequence: Int64,
        segmentStartedAt: Date,
        nextGapOrdinal: Int,
        anchorNanoseconds: UInt64,
        batchOrdinalBase: Int64 = 0
    ) {
        self.sessionID = sessionID
        self.generation = generation
        manifestOrdinalByRequest = Dictionary(
            orderedRequests.enumerated().map { ($0.element, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )
        self.batchOrdinalBase = batchOrdinalBase
        self.segmentOrdinal = segmentOrdinal
        self.segmentFirstSequence = segmentFirstSequence
        self.segmentStartedAt = segmentStartedAt
        isSegmentOpen = true
        self.nextGapOrdinal = nextGapOrdinal
        lastCommitAttemptNanoseconds = anchorNanoseconds
        lastStampedNanoseconds = anchorNanoseconds
    }

    /// 取得ループのbatch番号を保存上のbatch番号へ変換します。
    ///
    /// 責務: 世代内で0から始まるbatch番号へ、セッションに保存済みのbatch数を足します。
    /// - Parameter loopOrdinal: 取得ループが付けたbatch番号。
    /// - Returns: 保存上のbatch番号。
    func storedBatchOrdinal(_ loopOrdinal: Int64) -> Int64 {
        batchOrdinalBase + loopOrdinal
    }

    /// 受信した応答へ付ける単調時計の値を決めます。
    ///
    /// 責務: 区間内で単調時計の値が減らないよう、直近の値未満の読み取りを直近の値へ揃えます。
    /// - Parameter reading: 単調時計から読み取った値。
    /// - Returns: 区間内で減らない単調時計の値。
    mutating func stamp(_ reading: UInt64) -> UInt64 {
        lastStampedNanoseconds = max(reading, lastStampedNanoseconds)
        return lastStampedNanoseconds
    }

    /// 直近のcommitからの経過を返します。
    ///
    /// 責務: 単調時計の現在値から直近のcommit試行までの経過ナノ秒を求めます。
    /// - Parameter reading: 単調時計の現在値。
    /// - Returns: 経過ナノ秒。現在値が直近の値より小さい場合は0。
    func elapsedSinceLastCommit(at reading: UInt64) -> UInt64 {
        reading >= lastCommitAttemptNanoseconds ? reading - lastCommitAttemptNanoseconds : 0
    }

    /// commitを試みた時点を記録します。
    ///
    /// 責務: 次の経過判定の起点を更新します。
    /// - Parameter reading: commitを試みた時点の単調時計の値。
    mutating func markCommitAttempt(at reading: UInt64) {
        lastCommitAttemptNanoseconds = max(reading, lastCommitAttemptNanoseconds)
    }

    /// 次の欠損番号を払い出します。
    ///
    /// 責務: 欠損番号を1件払い出し、次の番号へ進めます。
    /// - Returns: 今回の欠損へ割り当てる番号。
    mutating func takeGapOrdinal() -> Int {
        defer { nextGapOrdinal += 1 }
        return nextGapOrdinal
    }

    /// 現在の区間を閉じた状態にします。
    ///
    /// 責務: 次の区間を開くまで受信の記録を受け付けない状態へ遷移させます。
    mutating func closeSegment() {
        isSegmentOpen = false
    }

    /// 次の区間を開いた状態にします。
    ///
    /// 責務: 新しい区間の番号・最初の記録順序・開始時刻・単調時計の起点へ切り替えます。
    /// - Parameters:
    ///   - ordinal: 新しい区間の番号。
    ///   - firstSequence: 新しい区間の最初の行へ割り当てる記録順序。
    ///   - startedAt: 新しい区間を開始した実時間。
    ///   - anchorNanoseconds: `startedAt` と同時に読んだ単調時計の値。
    mutating func openSegment(ordinal: Int, firstSequence: Int64, startedAt: Date, anchorNanoseconds: UInt64) {
        segmentOrdinal = ordinal
        segmentFirstSequence = firstSequence
        segmentStartedAt = startedAt
        isSegmentOpen = true
        lastStampedNanoseconds = anchorNanoseconds
        lastCommitAttemptNanoseconds = anchorNanoseconds
    }
}
