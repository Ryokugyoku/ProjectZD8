import Foundation

/// 連続取得区間と欠損の保存先DBを準備できない場合に明示的失敗を返します。
nonisolated struct UnavailableConnectionSessionSegmentationRepository: ConnectionSessionSegmentRepository,
    ConnectionSessionGapRepository {
    /// 利用不能境界を生成します。
    ///
    /// 責務: 永続化不能状態を表すRepositoryを構築します。
    init() {}

    /// 常に保存失敗を通知します。
    ///
    /// 責務: 区間の開始を利用不能エラーへ変換し、成功として扱いません。
    /// - Parameters:
    ///   - segment: 使用しない区間。
    ///   - sessionID: 使用しないセッション。
    /// - Throws: 常に `ConnectionSessionRepositoryError.unavailable`。
    func beginSegment(_ segment: ConnectionSessionSegment, for sessionID: ConnectionSessionID) throws {
        throw ConnectionSessionRepositoryError.unavailable
    }

    /// 常に保存失敗を通知します。
    ///
    /// 責務: 区間の終了を利用不能エラーへ変換し、成功として扱いません。
    /// - Parameters:
    ///   - segmentOrdinal: 使用しない区間番号。
    ///   - sessionID: 使用しないセッション。
    ///   - endedAt: 使用しない終了時刻。
    ///   - reason: 使用しない終了理由。
    ///   - lastSequence: 使用しない最終記録順序。
    /// - Throws: 常に `ConnectionSessionRepositoryError.unavailable`。
    func finishSegment(
        ordinal segmentOrdinal: Int,
        for sessionID: ConnectionSessionID,
        endedAt: Date,
        reason: ConnectionSessionSegmentEndReason,
        lastSequence: Int64?
    ) throws {
        throw ConnectionSessionRepositoryError.unavailable
    }

    /// 常に読取失敗を通知します。
    ///
    /// 責務: 区間の読取を利用不能エラーへ変換し、空データとして扱いません。
    /// - Parameter sessionID: 使用しないセッション。
    /// - Returns: 正常終了しません。
    /// - Throws: 常に `ConnectionSessionRepositoryError.unavailable`。
    func segments(for sessionID: ConnectionSessionID) throws -> [ConnectionSessionSegment] {
        throw ConnectionSessionRepositoryError.unavailable
    }

    /// 常に保存失敗を通知します。
    ///
    /// 責務: 欠損の保存を利用不能エラーへ変換し、成功として扱いません。
    /// - Parameters:
    ///   - gap: 使用しない欠損。
    ///   - sessionID: 使用しないセッション。
    /// - Throws: 常に `ConnectionSessionRepositoryError.unavailable`。
    func saveGap(_ gap: ConnectionSessionGap, for sessionID: ConnectionSessionID) throws {
        throw ConnectionSessionRepositoryError.unavailable
    }

    /// 常に保存失敗を通知します。
    ///
    /// 責務: 欠損の終了を利用不能エラーへ変換し、成功として扱いません。
    /// - Parameters:
    ///   - gapOrdinal: 使用しない欠損番号。
    ///   - sessionID: 使用しないセッション。
    ///   - endedAt: 使用しない終了時刻。
    ///   - followingSegmentOrdinal: 使用しない後続区間番号。
    /// - Throws: 常に `ConnectionSessionRepositoryError.unavailable`。
    func finishGap(
        ordinal gapOrdinal: Int,
        for sessionID: ConnectionSessionID,
        endedAt: Date,
        followingSegmentOrdinal: Int?
    ) throws {
        throw ConnectionSessionRepositoryError.unavailable
    }

    /// 常に読取失敗を通知します。
    ///
    /// 責務: 欠損の読取を利用不能エラーへ変換し、空データとして扱いません。
    /// - Parameter sessionID: 使用しないセッション。
    /// - Returns: 正常終了しません。
    /// - Throws: 常に `ConnectionSessionRepositoryError.unavailable`。
    func gaps(for sessionID: ConnectionSessionID) throws -> [ConnectionSessionGap] {
        throw ConnectionSessionRepositoryError.unavailable
    }
}
