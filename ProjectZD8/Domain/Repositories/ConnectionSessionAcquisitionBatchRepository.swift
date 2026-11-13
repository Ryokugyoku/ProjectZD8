/// session内の取得batchとPID request evidenceを永続化する能力です。
nonisolated protocol ConnectionSessionAcquisitionBatchRepository: Sendable {
    /// batch開始とpolicy選択済み要求列を未確定状態で保存します。
    ///
    /// 責務: 物理要求前のbatch intentを同じidentityで再試行可能な未確定証拠として保存します。
    /// - Parameters:
    ///   - evidence: terminal結果をまだ持たないbatch開始証拠。
    ///   - sessionID: batchを所有する接続session。
    /// - Throws: 重複、競合、親manifest欠落、または保存失敗。
    func beginBatch(
        _ evidence: AcquisitionBatchEvidence,
        for sessionID: ConnectionSessionID
    ) throws

    /// 選択済み要求が物理送信処理へ進むことを記録します。
    ///
    /// 責務: 1件の未開始要求を結果未確定のdispatch開始状態へ単調遷移させます。
    /// - Parameters:
    ///   - requestOrdinal: batch内要求順。
    ///   - batchIdentity: 要求を所有するbatch identity。
    ///   - sessionID: batchを所有する接続session。
    /// - Throws: batch/request欠落、重複、競合、または保存失敗。
    func markRequestDispatchBegun(
        requestOrdinal: Int,
        in batchIdentity: AcquisitionBatchIdentity,
        for sessionID: ConnectionSessionID
    ) throws

    /// 正応答Rawと対応するrequest terminal証拠を原子的に保存します。
    ///
    /// 責務: dispatch開始済み要求のRaw追記とresponded terminal化を単一永続化境界で確定します。
    /// - Parameters:
    ///   - observation: 既存Raw表へ追加する未デコード正応答。
    ///   - valueOutcome: 取得時定義による値評価結果。
    ///   - elapsedNanoseconds: 要求開始から正応答観測までの単調経過時間。
    ///   - reasonCode: transcript原文を含まない承認済み分類理由code。
    ///   - requestOrdinal: batch内要求順。
    ///   - batchIdentity: 要求を所有するbatch identity。
    ///   - sessionID: batchとRawを所有する接続session。
    /// - Returns: 採番済みRaw sequenceを参照するcanonical request evidence。
    /// - Throws: dispatch前、sealed、重複、競合、所有関係不一致、または原子保存失敗。
    func saveRespondedRequest(
        observation: OBDRawResponseObservation,
        valueOutcome: PIDRequestValueOutcome,
        elapsedNanoseconds: UInt64,
        reasonCode: String?,
        requestOrdinal: Int,
        in batchIdentity: AcquisitionBatchIdentity,
        for sessionID: ConnectionSessionID
    ) throws -> PIDRequestEvidence

    /// Rawを持たない排他的なrequest terminal証拠を保存します。
    ///
    /// 責務: dispatch開始済み要求を非responded terminal結果へ単調遷移させます。
    /// - Parameters:
    ///   - outcome: Rawを生成しない確認済みtransport結果。
    ///   - elapsedNanoseconds: 要求開始からterminal観測までの単調経過時間。回復時に不明なら `nil`。
    ///   - reasonCode: transcript原文を含まない承認済み分類理由code。
    ///   - requestOrdinal: batch内要求順。
    ///   - batchIdentity: 要求を所有するbatch identity。
    ///   - sessionID: batchを所有する接続session。
    /// - Returns: Raw sequenceを持たないcanonical request evidence。
    /// - Throws: responded指定、dispatch前、sealed、重複、競合、または保存失敗。
    func saveNonRespondedRequest(
        outcome: PIDRequestTransportOutcome,
        elapsedNanoseconds: UInt64?,
        reasonCode: String?,
        requestOrdinal: Int,
        in batchIdentity: AcquisitionBatchIdentity,
        for sessionID: ConnectionSessionID
    ) throws -> PIDRequestEvidence

    /// terminal request列とbatch終端を保存済み開始証拠へ反映します。
    ///
    /// 責務: partialを含むbatch terminal証拠を既存Raw参照の整合確認後に原子的に確定します。
    /// - Parameters:
    ///   - evidence: terminalまたは回復済みbatch証拠。
    ///   - sessionID: batchを所有する接続session。
    /// - Throws: batch/request欠落、Raw参照欠落、競合、または保存失敗。
    func finishBatch(
        _ evidence: AcquisitionBatchEvidence,
        for sessionID: ConnectionSessionID
    ) throws

    /// sessionのbatch証拠をordinal順で返します。
    ///
    /// 責務: 1件のsessionに保存されたpartialを含む全batchを安定順で復元します。
    /// - Parameter sessionID: 読取対象session。
    /// - Returns: batch ordinal昇順の取得証拠。
    /// - Throws: 保存値不正または読取失敗。
    func batches(for sessionID: ConnectionSessionID) throws -> [AcquisitionBatchEvidence]
}
