/// 取得済みRawと取得証跡をチャンク単位で原子的に永続化する能力です。
nonisolated protocol ConnectionSessionAcquisitionChunkRepository: Sendable {
    /// チャンク内のRawと取得証跡をすべて保存するか、何も保存しません。
    ///
    /// 責務: 1件のチャンクを検証し、1つの書き込みトランザクションで保存して失敗時は全体を取り消します。
    /// - Parameter chunk: 保存するチャンク。Rawも証跡も含まない場合は何も書かずに正常終了します。
    /// - Throws: 検証に失敗した理由、または保存先の失敗を表す
    ///   `ConnectionSessionAcquisitionChunkRepositoryError`。失敗時はチャンクの内容を1件も保存しません。
    func commit(_ chunk: ConnectionSessionAcquisitionChunk) throws
}
