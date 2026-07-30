/// session内の1回のpolling batchを識別します。
nonisolated struct AcquisitionBatchIdentity: Equatable, Hashable, Sendable {
    /// session内で0から単調増加するbatch番号です。
    let ordinal: Int64

    /// 非負のbatch番号を固定します。
    ///
    /// 責務: 1件のsession内batch番号を再試行可能な不変identityへ変換します。
    /// - Parameter ordinal: session内で重複しない非負のbatch番号。
    /// - Throws: 負数の場合は `AcquisitionBatchEvidenceError.invalidBatchOrdinal`。
    init(ordinal: Int64) throws {
        guard ordinal >= 0 else { throw AcquisitionBatchEvidenceError.invalidBatchOrdinal }
        self.ordinal = ordinal
    }
}
