import Foundation
@testable import ProjectZD8

/// 欠損をメモリ上に保持し、保存の失敗も指定できる欠損Repositoryです。
final class AcquisitionGapRepositorySpy: ConnectionSessionGapRepository, @unchecked Sendable {
    /// 保持内容を保護するロックです。
    private let lock = NSLock()
    /// 欠損の保存を失敗させるかどうかです。
    private let failsSave: Bool
    /// 欠損の終了を失敗させるかどうかです。
    private let failsFinish: Bool
    /// ロックで保護した保持中の欠損です。
    private var storedGaps: [ConnectionSessionGap]

    /// 既存の欠損と失敗指定を固定します。
    ///
    /// 責務: 既存欠損を持つメモリ上のRepositoryを構築します。
    /// - Parameters:
    ///   - gaps: 最初から保持する欠損。
    ///   - failsSave: 欠損の保存を失敗させる場合は `true`。
    ///   - failsFinish: 欠損の終了を失敗させる場合は `true`。
    init(gaps: [ConnectionSessionGap] = [], failsSave: Bool = false, failsFinish: Bool = false) {
        storedGaps = gaps
        self.failsSave = failsSave
        self.failsFinish = failsFinish
    }

    /// 欠損を保持します。
    ///
    /// 責務: 指定時は保存失敗を送出し、それ以外は欠損を末尾へ追加します。
    /// - Parameters:
    ///   - gap: 保存する欠損。
    ///   - sessionID: 所属セッション。
    /// - Throws: 失敗させる場合は `.unavailable`。
    func saveGap(_ gap: ConnectionSessionGap, for sessionID: ConnectionSessionID) throws {
        if failsSave { throw ConnectionSessionRepositoryError.unavailable }
        lock.withLock { storedGaps.append(gap) }
    }

    /// 欠損の終了を保持します。
    ///
    /// 責務: 指定番号の欠損を終了日時と後続区間付きへ置き換えます。
    /// - Parameters:
    ///   - gapOrdinal: 欠損番号。
    ///   - sessionID: 所属セッション。
    ///   - endedAt: 終了日時。
    ///   - followingSegmentOrdinal: 後続区間番号。
    /// - Throws: 失敗させる場合、または欠損が無い場合は `.unavailable`。
    func finishGap(ordinal gapOrdinal: Int, for sessionID: ConnectionSessionID, endedAt: Date, followingSegmentOrdinal: Int?) throws {
        if failsFinish { throw ConnectionSessionRepositoryError.unavailable }
        try lock.withLock {
            guard let index = storedGaps.firstIndex(where: { $0.gapOrdinal == gapOrdinal }) else {
                throw ConnectionSessionRepositoryError.unavailable
            }
            let gap = storedGaps[index]
            storedGaps[index] = ConnectionSessionGap(
                gapOrdinal: gap.gapOrdinal, precedingSegmentOrdinal: gap.precedingSegmentOrdinal,
                followingSegmentOrdinal: followingSegmentOrdinal, startedAt: gap.startedAt, endedAt: endedAt, cause: gap.cause
            )
        }
    }

    /// 保持中の欠損を返します。
    ///
    /// 責務: 保存順の保持内容を返します。
    /// - Parameter sessionID: 所属セッション。
    /// - Returns: 保持中の欠損。
    func gaps(for sessionID: ConnectionSessionID) throws -> [ConnectionSessionGap] {
        lock.withLock { storedGaps }
    }
}
