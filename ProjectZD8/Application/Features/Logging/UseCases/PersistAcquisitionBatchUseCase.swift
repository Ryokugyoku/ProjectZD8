import Foundation

/// 取得batchを安全に回復できなかったApplication上の理由です。
nonisolated enum PersistAcquisitionBatchError: Error, Equatable, Sendable {
    /// 要求が現在のpolling世代に属していません。
    case inactiveGeneration
    /// 回復対象のbatchが見つからないか、入力が保存済みの証跡と一致しません。
    case invalidInput
    /// metadataまたはRawの永続化に失敗しました。
    case persistenceFailure
}

/// プロセス終了などで終端まで確定できなかった保存済みの取得batchを回復します。
///
/// 応答の受信・評価・保存は `LiveTelemetryAcquisitionLoop` と `ConnectionSessionAcquisitionRecorder` が
/// チャンク単位で行います。この型は保存済みの未完了batchを終端状態へ確定する処理だけを持ちます。
actor PersistAcquisitionBatchUseCase {
    /// batch、request、Raw参照を保存するDomain repositoryです。
    private let repository: any ConnectionSessionAcquisitionBatchRepository

    /// 回復に使うrepositoryを固定します。
    ///
    /// 責務: 保存済みbatchの回復workflowの永続化境界を注入します。
    /// - Parameter repository: batch、request、Raw参照を保存するDomain repository。
    init(repository: any ConnectionSessionAcquisitionBatchRepository) {
        self.repository = repository
    }

    /// process終了後のopen batchをunknown terminalへ回復します。
    ///
    /// 責務: dispatch済み未確定要求だけをunknownとして保存しbatchをterminated状態へsealします。
    /// - Parameters:
    ///   - batchIdentity: 回復対象batch identity。
    ///   - sessionID: batchを所有するsession。
    ///   - completedAt: 回復処理がterminalを確定した実時間。
    /// - Returns: selected-only要求を保持したterminated batch証拠。
    /// - Throws: batch欠落、request保存失敗、またはbatch seal失敗。
    func recoverAfterTermination(
        batchIdentity: AcquisitionBatchIdentity,
        for sessionID: ConnectionSessionID,
        completedAt: Date
    ) throws -> AcquisitionBatchEvidence {
        do {
            guard let open = try repository.batches(for: sessionID).first(where: {
                $0.identity == batchIdentity && $0.completionState == nil
            }) else {
                throw PersistAcquisitionBatchError.invalidInput
            }
            var recovered = open.requests
            for request in open.requests where request.dispatchState == .dispatchBegun {
                recovered[request.requestOrdinal] = try repository.saveNonRespondedRequest(
                    outcome: .unknownAfterTermination,
                    elapsedNanoseconds: nil,
                    reasonCode: "process_terminated_after_dispatch",
                    requestOrdinal: request.requestOrdinal,
                    in: batchIdentity,
                    for: sessionID
                )
            }
            let terminal = try AcquisitionBatchEvidence(
                identity: open.identity,
                generation: open.generation,
                policyTick: open.policyTick,
                isSelectionEvaluationComplete: open.isSelectionEvaluationComplete,
                startedAt: open.startedAt,
                completionState: .terminatedUnknown,
                completedAt: completedAt,
                failure: .processTerminated,
                requests: recovered
            )
            try repository.finishBatch(terminal, for: sessionID)
            return terminal
        } catch let error as PersistAcquisitionBatchError {
            throw error
        } catch {
            throw PersistAcquisitionBatchError.persistenceFailure
        }
    }
}
