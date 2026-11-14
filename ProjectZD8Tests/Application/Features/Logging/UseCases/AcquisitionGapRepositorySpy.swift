import Foundation
@testable import ProjectZD8

/// 欠損をメモリ上に保持し、保存の失敗も指定できる欠損Repositoryです。
final class AcquisitionGapRepositorySpy: ConnectionSessionGapRepository, @unchecked Sendable {
    /// 保持内容を保護するロックです。
    private let lock = NSLock()
    /// 欠損の保存を失敗させるかどうかです。
    private let failsSave: Bool
    /// ロックで保護した保持中の欠損です。
    private var storedGaps: [ConnectionSessionGap]

    /// 既存の欠損と失敗指定を固定します。
    ///
    /// 責務: 既存欠損を持つメモリ上のRepositoryを構築します。
    /// - Parameters:
    ///   - gaps: 最初から保持する欠損。
    ///   - failsSave: 欠損の保存を失敗させる場合は `true`。
    init(gaps: [ConnectionSessionGap] = [], failsSave: Bool = false) {
        storedGaps = gaps
        self.failsSave = failsSave
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

    /// 欠損の終了を受け付けます。
    ///
    /// 責務: 記録の検証で使わない終了を変更なしで完了します。
    /// - Parameters:
    ///   - gapOrdinal: 欠損番号。
    ///   - sessionID: 所属セッション。
    ///   - endedAt: 終了日時。
    ///   - followingSegmentOrdinal: 後続区間番号。
    func finishGap(ordinal gapOrdinal: Int, for sessionID: ConnectionSessionID, endedAt: Date, followingSegmentOrdinal: Int?) throws {}

    /// 保持中の欠損を返します。
    ///
    /// 責務: 保存順の保持内容を返します。
    /// - Parameter sessionID: 所属セッション。
    /// - Returns: 保持中の欠損。
    func gaps(for sessionID: ConnectionSessionID) throws -> [ConnectionSessionGap] {
        lock.withLock { storedGaps }
    }
}
