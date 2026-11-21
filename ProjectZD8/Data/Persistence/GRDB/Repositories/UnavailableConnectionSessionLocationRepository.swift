import Foundation

/// 位置の保存先DBを準備できない場合に明示的失敗を返します。
nonisolated struct UnavailableConnectionSessionLocationRepository: ConnectionSessionLocationRepository {
    /// 利用不能境界を生成します。
    ///
    /// 責務: 永続化不能状態を表すRepositoryを構築します。
    init() {}

    /// 常に保存失敗を通知します。
    ///
    /// 責務: 位置の保存を利用不能エラーへ変換し、成功として扱いません。
    /// - Parameters:
    ///   - fix: 使用しない位置。
    ///   - sessionID: 使用しないセッション。
    /// - Throws: 常に `ConnectionSessionRepositoryError.unavailable`。
    func appendSample(_ fix: LocationFix, for sessionID: ConnectionSessionID) throws {
        throw ConnectionSessionRepositoryError.unavailable
    }

    /// 常に読取失敗を通知します。
    ///
    /// 責務: 位置の読取を利用不能エラーへ変換し、空データとして扱いません。
    /// - Parameter sessionID: 使用しないセッション。
    /// - Returns: 正常終了しません。
    /// - Throws: 常に `ConnectionSessionRepositoryError.unavailable`。
    func samples(for sessionID: ConnectionSessionID) throws -> [ConnectionSessionLocationSample] {
        throw ConnectionSessionRepositoryError.unavailable
    }

    /// 常に保存失敗を通知します。
    ///
    /// 責務: 位置記録事象の保存を利用不能エラーへ変換し、成功として扱いません。
    /// - Parameters:
    ///   - kind: 使用しない種類。
    ///   - occurredAt: 使用しない時刻。
    ///   - sessionID: 使用しないセッション。
    /// - Throws: 常に `ConnectionSessionRepositoryError.unavailable`。
    func appendEvent(
        _ kind: ConnectionSessionLocationEventKind,
        occurredAt: Date,
        for sessionID: ConnectionSessionID
    ) throws {
        throw ConnectionSessionRepositoryError.unavailable
    }

    /// 常に読取失敗を通知します。
    ///
    /// 責務: 位置記録事象の読取を利用不能エラーへ変換し、空データとして扱いません。
    /// - Parameter sessionID: 使用しないセッション。
    /// - Returns: 正常終了しません。
    /// - Throws: 常に `ConnectionSessionRepositoryError.unavailable`。
    func events(for sessionID: ConnectionSessionID) throws -> [ConnectionSessionLocationEvent] {
        throw ConnectionSessionRepositoryError.unavailable
    }
}
