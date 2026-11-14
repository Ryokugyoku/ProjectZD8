import Foundation

/// 保存待ちバッファ内の1周回分の取得batchと、その周回で受信した応答です。
nonisolated struct AcquisitionBufferedBatch: Equatable, Sendable {
    /// 保存待ちbatch内の1件の要求です。
    struct Request: Equatable, Sendable {
        /// manifestの要求順における位置です。
        let manifestPIDOrdinal: Int
        /// Domainのrequest結果です。未終了の場合は `nil` です。
        var transportOutcome: PIDRequestTransportOutcome?
        /// 正応答の値評価結果です。
        var valueOutcome: PIDRequestValueOutcome = .notEvaluated
        /// 正応答が参照する `raws` 内の位置です。
        var rawIndex: Int?
        /// 要求送信から結果受信までの単調経過時間です。
        var elapsedNanoseconds: UInt64?
        /// 正応答以外の分類理由codeです。
        var reasonCode: String?
    }

    /// セッション内のbatch identityです。
    let identity: AcquisitionBatchIdentity
    /// batchを生成した取得世代です。
    let generation: UInt
    /// polling policyが評価した周回番号です。
    let policyTick: UInt
    /// 周回を開始した実時間です。
    let startedAt: Date
    /// 周回内の要求順に並ぶ要求です。
    private(set) var requests: [Request]
    /// 周回内で受信した正応答です。受信順に並びます。
    private(set) var raws: [AcquisitionBufferedRaw] = []
    /// 終端状態です。未完了の場合は `nil` です。
    private(set) var completionState: AcquisitionBatchCompletionState?
    /// 終端を確定した実時間です。
    private(set) var completedAt: Date?
    /// 終端の失敗理由です。
    private(set) var failure: AcquisitionBatchFailure?

    /// 周回開始時点の未完了batchを生成します。
    ///
    /// 責務: 周回の識別子と要求のmanifest位置を未完了状態へ固定します。
    /// - Parameters:
    ///   - identity: セッション内のbatch identity。
    ///   - generation: batchを生成した取得世代。
    ///   - policyTick: polling policyが評価した周回番号。
    ///   - startedAt: 周回を開始した実時間。
    ///   - manifestPIDOrdinals: 周回内の要求順に並ぶmanifest位置。
    init(
        identity: AcquisitionBatchIdentity,
        generation: UInt,
        policyTick: UInt,
        startedAt: Date,
        manifestPIDOrdinals: [Int]
    ) {
        self.identity = identity
        self.generation = generation
        self.policyTick = policyTick
        self.startedAt = startedAt
        requests = manifestPIDOrdinals.map { Request(manifestPIDOrdinal: $0) }
    }

    /// 終端状態まで確定しているかを返します。
    ///
    /// 責務: チャンクへ入れてよいbatchかを判定します。
    var isTerminal: Bool { completionState != nil }

    /// 次に結果を受け付ける要求順を返します。
    ///
    /// 責務: 周回内で最初に未終了の要求位置を返します。全要求が終了済みなら `nil`。
    var nextRequestOrdinal: Int? { requests.firstIndex { $0.transportOutcome == nil } }

    /// 要求1件の終端結果を記録します。
    ///
    /// 責務: 次の未終了要求へ結果と任意の正応答を対応付けます。
    /// - Parameters:
    ///   - requestOrdinal: 結果が属する周回内の要求順。
    ///   - transportOutcome: Domainのrequest結果。
    ///   - valueOutcome: 正応答の値評価結果。
    ///   - elapsedNanoseconds: 要求送信から結果受信までの単調経過時間。
    ///   - reasonCode: 正応答以外の分類理由code。
    ///   - raw: 正応答の場合の保存待ち応答。
    /// - Throws: 終端済みbatch、順序不一致、正応答とRawの有無が一致しない場合は `.invalidInput`。
    mutating func record(
        requestOrdinal: Int,
        transportOutcome: PIDRequestTransportOutcome,
        valueOutcome: PIDRequestValueOutcome,
        elapsedNanoseconds: UInt64,
        reasonCode: String?,
        raw: AcquisitionBufferedRaw?
    ) throws {
        guard !isTerminal, nextRequestOrdinal == requestOrdinal,
              (transportOutcome == .responded) == (raw != nil) else {
            throw LiveTelemetryAcquisitionRecordingError.invalidInput
        }
        if let raw {
            requests[requestOrdinal].rawIndex = raws.count
            raws.append(raw)
        }
        requests[requestOrdinal].transportOutcome = transportOutcome
        requests[requestOrdinal].valueOutcome = valueOutcome
        requests[requestOrdinal].elapsedNanoseconds = elapsedNanoseconds
        requests[requestOrdinal].reasonCode = reasonCode
    }

    /// 全要求が終わった周回を終端状態へ確定します。
    ///
    /// 責務: request結果列から完了または明示的な部分失敗を決めて終端状態へ遷移させます。
    /// - Parameters:
    ///   - completedAt: 終端を確定した実時間。
    ///   - classifier: request結果列をbatch失敗理由へ集約する分類器。
    /// - Throws: 終端済み、または未終了の要求が残る場合は `.invalidInput`。
    mutating func complete(at completedAt: Date, classifier: AcquisitionTransportOutcomeClassifier) throws {
        guard !isTerminal, nextRequestOrdinal == nil else {
            throw LiveTelemetryAcquisitionRecordingError.invalidInput
        }
        seal(failure: classifier.batchFailure(for: requests.compactMap(\.transportOutcome)), at: completedAt)
    }

    /// 周回の途中で取得を終えたbatchを打ち切ります。
    ///
    /// 責務: 未送信の要求を選択のみの状態で残し、取消による失敗として終端状態へ遷移させます。
    /// 全要求が終わっていた場合は通常の完了と同じ規則で終端状態へ遷移させます。
    /// - Parameters:
    ///   - completedAt: 打ち切りを確定した実時間。
    ///   - classifier: 全要求が終わっていた場合に使う分類器。
    mutating func abandon(at completedAt: Date, classifier: AcquisitionTransportOutcomeClassifier) {
        guard !isTerminal else { return }
        if nextRequestOrdinal == nil {
            seal(failure: classifier.batchFailure(for: requests.compactMap(\.transportOutcome)), at: completedAt)
        } else {
            seal(failure: .cancelled, at: completedAt)
        }
    }

    /// 失敗理由と終端時刻を確定します。
    ///
    /// 責務: 失敗理由の有無から完了または失敗の終端状態を決め、開始より前にならない終端時刻を付けます。
    /// - Parameters:
    ///   - failure: batchの失敗理由。失敗なしは `nil`。
    ///   - completedAt: 終端を確定した実時間。
    private mutating func seal(failure: AcquisitionBatchFailure?, at completedAt: Date) {
        self.failure = failure
        completionState = failure == nil ? .completed : .failed
        self.completedAt = max(completedAt, startedAt)
    }

    /// 連番を割り当てて保存用のbatch証跡へ変換します。
    ///
    /// 責務: 受信順の正応答へ連番を振り、request証跡のRaw参照を確定します。
    /// - Parameter firstSequence: このbatchの最初の正応答へ割り当てる記録順序。
    /// - Returns: 採番済みRaw entryと終端状態のbatch証跡。
    /// - Throws: 未完了batch、またはDomain不変条件に違反する場合のエラー。
    func evidence(
        firstSequence: Int64
    ) throws -> (rawEntries: [ConnectionSessionRawLogEntry], batch: AcquisitionBatchEvidence) {
        guard isTerminal else { throw LiveTelemetryAcquisitionRecordingError.invalidInput }
        let entries = raws.enumerated().map { $0.element.entry(sequence: firstSequence + Int64($0.offset)) }
        let evidences = try requests.enumerated().map { ordinal, request in
            try PIDRequestEvidence(
                requestOrdinal: ordinal,
                manifestPIDOrdinal: request.manifestPIDOrdinal,
                dispatchState: request.transportOutcome == nil ? .selectedOnly : .terminal,
                transportOutcome: request.transportOutcome,
                valueOutcome: request.valueOutcome,
                rawSequence: request.rawIndex.map { firstSequence + Int64($0) },
                elapsedNanoseconds: request.elapsedNanoseconds,
                reasonCode: request.reasonCode
            )
        }
        let batch = try AcquisitionBatchEvidence(
            identity: identity,
            generation: generation,
            policyTick: policyTick,
            isSelectionEvaluationComplete: true,
            startedAt: startedAt,
            completionState: completionState,
            completedAt: completedAt,
            failure: failure,
            requests: evidences
        )
        return (entries, batch)
    }
}
