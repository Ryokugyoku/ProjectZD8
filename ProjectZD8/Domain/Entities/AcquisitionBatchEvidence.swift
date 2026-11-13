import Foundation

/// policy evaluation完了後に導出できるPID選択状態です。
nonisolated enum AcquisitionPIDSelection: Equatable, Sendable {
    /// batchの送信対象として選択されました。
    case requested
    /// 完了済みpolicy evaluationにより意図的に選択されませんでした。
    case intentionalPollingOmission
}

/// batchが永続的に確定した終端状態です。
nonisolated enum AcquisitionBatchCompletionState: String, Equatable, Sendable {
    /// 全選択要求のterminal結果を保存して完了しました。
    case completed
    /// 観測可能な失敗により一部または全部の要求を完了できませんでした。
    case failed
    /// process終了後の回復でbatch終端だけを確定しました。
    case terminatedUnknown
}

/// batch全体を完了できなかったApplication上の分類です。
nonisolated enum AcquisitionBatchFailure: String, Equatable, Sendable {
    /// 通信境界をbatch途中で利用できなくなりました。
    case transportUnavailable
    /// 明示取消しによりbatchを停止しました。
    case cancelled
    /// Rawまたはrequest evidenceを完全に保存できませんでした。
    case persistenceFailure
    /// queue飽和により新規物理要求を開始せず停止しました。
    case backpressureStopped
    /// process終了後の回復まで終端を観測できませんでした。
    case processTerminated
    /// 承認済み分類へ変換できない結果がありました。
    case unclassifiedResult
}

/// 1回のpolling policy evaluationとPID要求列の永続証拠です。
nonisolated struct AcquisitionBatchEvidence: Equatable, Sendable {
    /// session内のbatch identityです。
    let identity: AcquisitionBatchIdentity
    /// stale callback拒否に使用した取得世代です。
    let generation: UInt
    /// policyが評価した単調tickです。
    let policyTick: UInt
    /// policy evaluationが完了して選択集合を確定できたかを示します。
    let isSelectionEvaluationComplete: Bool
    /// batch開始を観測した実時間です。
    let startedAt: Date
    /// batchのterminal状態です。`nil` は未確定batchを表します。
    let completionState: AcquisitionBatchCompletionState?
    /// terminal状態を確定した実時間です。
    let completedAt: Date?
    /// batch全体の失敗分類です。
    let failure: AcquisitionBatchFailure?
    /// policyで選択された要求の順序付き証拠です。
    let requests: [PIDRequestEvidence]

    /// batch metadataと要求列の整合を検証して固定します。
    ///
    /// 責務: 1回のpolicy tickをpartialとterminationを保持できる不変batch証拠へ変換します。
    /// - Parameters:
    ///   - identity: session内batch identity。
    ///   - generation: 取得世代。
    ///   - policyTick: policyの単調tick。
    ///   - isSelectionEvaluationComplete: policy評価完了の有無。
    ///   - startedAt: batch開始実時間。
    ///   - completionState: terminal状態、または未確定を示す `nil`。
    ///   - completedAt: terminal確定実時間。
    ///   - failure: batch-level failure。
    ///   - requests: policy選択順の要求証拠。
    /// - Throws: terminal、時系列、ordinal、不変条件が不正な場合は `AcquisitionBatchEvidenceError`。
    init(
        identity: AcquisitionBatchIdentity,
        generation: UInt,
        policyTick: UInt,
        isSelectionEvaluationComplete: Bool,
        startedAt: Date,
        completionState: AcquisitionBatchCompletionState?,
        completedAt: Date?,
        failure: AcquisitionBatchFailure?,
        requests: [PIDRequestEvidence]
    ) throws {
        guard requests.enumerated().allSatisfy({ $0.offset == $0.element.requestOrdinal }),
              Set(requests.map(\.manifestPIDOrdinal)).count == requests.count else {
            throw AcquisitionBatchEvidenceError.invalidRequestOrdinal
        }
        switch completionState {
        case nil:
            guard completedAt == nil, failure == nil else {
                throw AcquisitionBatchEvidenceError.invalidBatchState
            }
        case .completed:
            guard let completedAt, completedAt >= startedAt, failure == nil,
                  isSelectionEvaluationComplete,
                  requests.allSatisfy({ $0.dispatchState == .terminal }) else {
                throw AcquisitionBatchEvidenceError.invalidBatchState
            }
        case .failed, .terminatedUnknown:
            guard let completedAt, completedAt >= startedAt, failure != nil else {
                throw AcquisitionBatchEvidenceError.invalidBatchState
            }
        }
        self.identity = identity
        self.generation = generation
        self.policyTick = policyTick
        self.isSelectionEvaluationComplete = isSelectionEvaluationComplete
        self.startedAt = startedAt
        self.completionState = completionState
        self.completedAt = completedAt
        self.failure = failure
        self.requests = requests
    }

    /// manifest PID位置がこのbatchで選択されたかを返します。
    ///
    /// 責務: 完了済みpolicy evaluationと選択要求集合を要求または意図的省略へ変換します。
    /// - Parameter manifestPIDOrdinal: 判定するmanifest ordered PID位置。
    /// - Returns: policy評価完了時の選択状態。未完了または負数では `nil`。
    func selection(for manifestPIDOrdinal: Int) -> AcquisitionPIDSelection? {
        guard isSelectionEvaluationComplete, manifestPIDOrdinal >= 0 else { return nil }
        return requests.contains(where: { $0.manifestPIDOrdinal == manifestPIDOrdinal })
            ? .requested
            : .intentionalPollingOmission
    }
}

/// batchまたは要求証拠の不変条件違反です。
nonisolated enum AcquisitionBatchEvidenceError: Error, Equatable, Sendable {
    /// batch ordinalが負数です。
    case invalidBatchOrdinal
    /// requestまたはmanifest PID ordinalが負数、重複、非連続です。
    case invalidRequestOrdinal
    /// dispatch段階とterminal結果の組が不正です。
    case invalidRequestState
    /// `responded`に既存Raw sequence参照がありません。
    case respondedRawReferenceMissing
    /// 非応答結果が値評価またはRaw参照を保持しています。
    case nonResponseContainsValue
    /// batch terminal状態、時刻、failureの組が不正です。
    case invalidBatchState
    /// 空のreason codeが指定されました。
    case emptyReasonCode
}
