/// policy選択後の1要求が物理通信境界をどこまで進んだかを表します。
nonisolated enum PIDRequestDispatchState: String, Equatable, Sendable {
    /// policyで選択されたが送信処理は開始されていません。
    case selectedOnly
    /// 送信処理へ進むことを永続的に許可しました。
    case dispatchBegun
    /// transport結果が排他的に確定しました。
    case terminal
}

/// 1件のPID要求について通信境界が確定できた排他結果です。
nonisolated enum PIDRequestTransportOutcome: String, Equatable, Sendable {
    /// 要求と一致する正応答payloadを取得しました。
    case responded
    /// protocol上の明示証拠により非対応を確認しました。
    case unsupported
    /// 対象要求の期限内にterminal応答を取得できませんでした。
    case timedOut
    /// 明示的なtask取消しを対象要求で観測しました。
    case cancelled
    /// 対象要求中に通信境界を失いました。
    case transportFailure
    /// 永続化済みdispatch開始後にprocess終了して結果を確定できませんでした。
    case unknownAfterTermination
    /// 応答文字列は観測したものの承認済み結果へ分類できませんでした。
    case unclassifiedResponse
}

/// 取得時PID definition snapshotによる値評価結果です。
nonisolated enum PIDRequestValueOutcome: String, Equatable, Sendable {
    /// payloadを値として評価していません。
    case notEvaluated
    /// finite値へdecodeでき取得時の宣言済み範囲を満たしました。
    case decodedValid
    /// 取得時definitionでpayloadをfinite値へdecodeできませんでした。
    case decodeFailure
    /// finite値へdecodeできましたが取得時の宣言済み範囲外でした。
    case invalidValue
}

/// 1件の選択済みPID要求に対する永続的な進行証拠です。
nonisolated struct PIDRequestEvidence: Equatable, Sendable {
    /// batch内で0から連続する要求順です。
    let requestOrdinal: Int
    /// session manifestのordered PID集合を参照する位置です。
    let manifestPIDOrdinal: Int
    /// 要求が物理通信境界をどこまで進んだかを示します。
    let dispatchState: PIDRequestDispatchState
    /// terminal時の通信結果です。
    let transportOutcome: PIDRequestTransportOutcome?
    /// 取得時definitionによる値評価結果です。
    let valueOutcome: PIDRequestValueOutcome
    /// `responded`時だけ参照する既存Raw sequenceです。
    let rawSequence: Int64?
    /// 要求開始からterminal観測までの単調経過時間です。
    let elapsedNanoseconds: UInt64?
    /// transcript原文を保存せず承認済み分類理由を識別するcodeです。
    let reasonCode: String?

    /// 要求進行と排他結果を整合する不変証拠へ固定します。
    ///
    /// 責務: 1件の選択済み要求についてdispatch、transport、value、Raw参照の整合性を検証します。
    /// - Parameters:
    ///   - requestOrdinal: batch内で0から連続する要求順。
    ///   - manifestPIDOrdinal: manifest ordered PID集合の非負位置。
    ///   - dispatchState: 要求の進行段階。
    ///   - transportOutcome: terminal時の排他通信結果。
    ///   - valueOutcome: 取得時definitionによる値評価結果。
    ///   - rawSequence: `responded`時だけ指定する非負Raw sequence。
    ///   - elapsedNanoseconds: terminal観測までの任意の単調経過時間。
    ///   - reasonCode: 承認済み分類理由code。
    /// - Throws: ordinalまたは結果の組が不正な場合は `AcquisitionBatchEvidenceError`。
    init(
        requestOrdinal: Int,
        manifestPIDOrdinal: Int,
        dispatchState: PIDRequestDispatchState,
        transportOutcome: PIDRequestTransportOutcome?,
        valueOutcome: PIDRequestValueOutcome,
        rawSequence: Int64?,
        elapsedNanoseconds: UInt64?,
        reasonCode: String?
    ) throws {
        guard requestOrdinal >= 0, manifestPIDOrdinal >= 0 else {
            throw AcquisitionBatchEvidenceError.invalidRequestOrdinal
        }
        guard reasonCode?.isEmpty != true else {
            throw AcquisitionBatchEvidenceError.emptyReasonCode
        }
        switch dispatchState {
        case .selectedOnly, .dispatchBegun:
            guard transportOutcome == nil, valueOutcome == .notEvaluated,
                  rawSequence == nil, elapsedNanoseconds == nil else {
                throw AcquisitionBatchEvidenceError.invalidRequestState
            }
        case .terminal:
            guard let transportOutcome else {
                throw AcquisitionBatchEvidenceError.invalidRequestState
            }
            if transportOutcome == .responded {
                guard let rawSequence, rawSequence >= 0 else {
                    throw AcquisitionBatchEvidenceError.respondedRawReferenceMissing
                }
            } else {
                guard rawSequence == nil, valueOutcome == .notEvaluated else {
                    throw AcquisitionBatchEvidenceError.nonResponseContainsValue
                }
            }
        }
        self.requestOrdinal = requestOrdinal
        self.manifestPIDOrdinal = manifestPIDOrdinal
        self.dispatchState = dispatchState
        self.transportOutcome = transportOutcome
        self.valueOutcome = valueOutcome
        self.rawSequence = rawSequence
        self.elapsedNanoseconds = elapsedNanoseconds
        self.reasonCode = reasonCode
    }
}
