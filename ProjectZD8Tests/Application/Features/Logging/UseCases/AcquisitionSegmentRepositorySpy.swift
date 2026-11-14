import Foundation
@testable import ProjectZD8

/// 連続取得区間をメモリ上に保持し、終了の失敗も指定できる区間Repositoryです。
final class AcquisitionSegmentRepositorySpy: ConnectionSessionSegmentRepository, @unchecked Sendable {
    /// 保持内容を保護するロックです。
    private let lock = NSLock()
    /// 区間の終了を失敗させるかどうかです。
    private let failsFinish: Bool
    /// この件数の開始を受け付けた後の開始を失敗させます。`nil` なら失敗させません。
    private let failingBeginsAfter: Int?
    /// ロックで保護した受け付けた開始の件数です。
    private var acceptedBegins = 0
    /// ロックで保護した保持中の区間です。
    private var storedSegments: [ConnectionSessionSegment]

    /// 既存の区間と失敗指定を固定します。
    ///
    /// 責務: 既存区間を持つメモリ上のRepositoryを構築します。
    /// - Parameters:
    ///   - segments: 最初から保持する区間。
    ///   - failsFinish: 区間の終了を失敗させる場合は `true`。
    ///   - failingBeginsAfter: この件数の開始を受け付けた後の開始を失敗させます。`nil` なら失敗させません。
    init(segments: [ConnectionSessionSegment] = [], failsFinish: Bool = false, failingBeginsAfter: Int? = nil) {
        storedSegments = segments
        self.failsFinish = failsFinish
        self.failingBeginsAfter = failingBeginsAfter
    }

    /// 区間の開始を保持します。
    ///
    /// 責務: 指定件数を超えた開始は保存失敗を送出し、それ以外は開始した区間を末尾へ追加します。
    /// - Parameters:
    ///   - segment: 開始した区間。
    ///   - sessionID: 所属セッション。
    /// - Throws: 失敗させる場合は `.unavailable`。
    func beginSegment(_ segment: ConnectionSessionSegment, for sessionID: ConnectionSessionID) throws {
        try lock.withLock {
            if let failingBeginsAfter, acceptedBegins >= failingBeginsAfter { throw ConnectionSessionRepositoryError.unavailable }
            acceptedBegins += 1
            storedSegments.append(segment)
        }
    }

    /// 区間の終了を保持します。
    ///
    /// 責務: 指定番号の区間を終了日時・理由・最終連番付きへ置き換えます。
    /// - Parameters:
    ///   - segmentOrdinal: 終える区間番号。
    ///   - sessionID: 所属セッション。
    ///   - endedAt: 終了日時。
    ///   - reason: 終了理由。
    ///   - lastSequence: 区間の最終連番。
    /// - Throws: 失敗させる場合、または区間が無い場合は `.unavailable`。
    func finishSegment(
        ordinal segmentOrdinal: Int,
        for sessionID: ConnectionSessionID,
        endedAt: Date,
        reason: ConnectionSessionSegmentEndReason,
        lastSequence: Int64?
    ) throws {
        if failsFinish { throw ConnectionSessionRepositoryError.unavailable }
        try lock.withLock {
            guard let index = storedSegments.firstIndex(where: { $0.segmentOrdinal == segmentOrdinal }) else {
                throw ConnectionSessionRepositoryError.unavailable
            }
            let segment = storedSegments[index]
            storedSegments[index] = ConnectionSessionSegment(
                segmentOrdinal: segment.segmentOrdinal, startReason: segment.startReason,
                acquisitionMode: segment.acquisitionMode, startedAt: segment.startedAt,
                monotonicAnchorNanoseconds: segment.monotonicAnchorNanoseconds, firstSequence: segment.firstSequence,
                endedAt: endedAt, endReason: reason, lastSequence: lastSequence
            )
        }
    }

    /// 保持中の区間を返します。
    ///
    /// 責務: 区間番号順の保持内容を返します。
    /// - Parameter sessionID: 所属セッション。
    /// - Returns: 保持中の区間。
    func segments(for sessionID: ConnectionSessionID) throws -> [ConnectionSessionSegment] {
        lock.withLock { storedSegments }
    }
}
