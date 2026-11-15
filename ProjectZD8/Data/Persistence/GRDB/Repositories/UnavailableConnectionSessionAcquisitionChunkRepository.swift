/// 取得チャンクの保存先DBを準備できない場合に明示的失敗を返します。
nonisolated struct UnavailableConnectionSessionAcquisitionChunkRepository: ConnectionSessionAcquisitionChunkRepository {
    /// 利用不能境界を生成します。
    ///
    /// 責務: 永続化不能状態を表すRepositoryを構築します。
    init() {}

    /// 常に保存失敗を通知します。
    ///
    /// 責務: 空チャンクを含むすべてのチャンク保存を利用不能エラーへ変換し、成功として扱いません。
    /// - Parameter chunk: 使用しないチャンク。
    /// - Throws: 常に `ConnectionSessionAcquisitionChunkRepositoryError.unavailable`。
    func commit(_ chunk: ConnectionSessionAcquisitionChunk) throws {
        throw ConnectionSessionAcquisitionChunkRepositoryError.unavailable
    }
}
