import Foundation

/// PID要求を1件ずつ送り、結果を受けた処理の中で次の1件を送る応答駆動の取得ループです。
///
/// 要求の間に待機を挟みません。1周回を1 batchとし、周回の全要求が終わると周回番号を進めて
/// `OBDPIDPollingPolicy` で次の周回の要求列を選びます。正応答のあった最初の周回で応答したPIDだけを以後の対象にします。
/// 取得対象は開始時に渡された定義(車両別の収集トグルが有効なPIDだけ)の部分集合で、ループが要求を足すことはありません。
///
/// 状態遷移: 取得中 → (途切れ) 回復中(段階と試行回数) → (段階を使い切る) 一時停止(猶予待ち) →
/// 復帰して取得中へ戻る、または猶予切れで終了。停止の指示(取消)はどの状態からでも即座に終了します。
/// 途切れの判定は要求1件の結果を受けるたびに `LiveTelemetryReceiveTracker`(単調時計と `AcquisitionStallPolicy`)で行い、
/// 回復と一時停止は `LiveTelemetryAcquisitionRecovery` が行います。一時停止中だけは、猶予切れの検知と
/// 10秒ごとの定期的な復帰の試行のために `LiveTelemetryDeadlineWaitPort` の待ちを使います(要求の間に待機を挟まない方針の例外)。
///
/// actor再入の方針:
/// - 取得処理は1世代につき1つのTaskで直列に進みます。要求の送信・記録・周回の切替は同じTask内の
///   `await` の連鎖なので、互いに追い越しません。
/// - `start` は前の世代のTaskを取り消し、新しいTaskは前のTaskの終了(記録の終了と通信資源の解放)を
///   待ってから始まります。`stop` も取消後にTaskの終了を待ちます。どちらも、待っている間に別の
///   `start` が来た場合に備え、保持しているTaskが入れ替わっていないかを確かめてから状態を片付けます。
/// - `flush` は取得Taskの要求待ちの間に実行され得ます。記録先は同じactorで直列に処理し、未完了の周回は
///   次のチャンクへ持ち越すため、取得Taskの前提を崩しません。失敗は世代ごとに記録し、取得Taskが次の受信後に
///   保存失敗として終了します。区間の切替(`endSegment` / `beginSegment`)は取得Taskだけが呼び、記録先の中で
///   flushと交互に実行されます。区間が閉じている間のflushは保存するものが無く成功します。
/// - 回復中・一時停止中に届いた停止の指示は取得Taskの取消として伝わります。回復操作と確認要求は
///   トランスポートの応答待ちの上限で返り、その直後に取消を確かめて終了します。一時停止中は起床理由の
///   ストリームの待ちが取消で終わり、即座に終了します。
/// - `notify` は一時停止中だけ起床理由を取得Taskへ渡し、それ以外の状態では捨てます(取得中は要求の結果ごとに、
///   回復中は回復操作の完了ごとに判定するためです)。リンク復帰と猶予切れの期限が重なった場合は、届いた順に
///   処理し、どちらでも先に単調時計で猶予を判定します。猶予内(ちょうど3分を含む)なら復帰を試します。
actor LiveTelemetryAcquisitionLoop {
    /// 1件ずつ要求を送る読取部品です。
    private let reader: OBDPIDSingleRequestReader
    /// 終了時に接続資源を解放するPID取得境界です。
    private let telemetry: any OBDPIDTelemetryPort
    /// 正応答を評価する部品です。
    private let decoder: OBDPIDPayloadDecoder
    /// 周回ごとの要求列を選ぶ方針です。
    private let pollingPolicy: OBDPIDPollingPolicy
    /// 受信結果を記録する境界です。記録しない経路では `nil` です。
    private let recorder: (any LiveTelemetryAcquisitionRecordingPort)?
    /// batch開始日時と表示用観測日時を供給するclockです。
    private let now: @Sendable () -> Date
    /// 要求ごとの経過と途切れを測る単調時計です。
    private let clock: any MonotonicClockPort
    /// 途切れた後の回復と一時停止の手順です。
    private let recovery: LiveTelemetryAcquisitionRecovery
    /// 一時停止中の取得Taskへ起床理由を渡す通り道です。
    private let pauseChannel = LiveTelemetryPauseWakeChannel()
    /// 取得記録を行うかどうかです。
    nonisolated let recordsAcquisition: Bool
    /// 現在の世代の取得Taskです。
    private var runningTask: Task<LiveTelemetryAcquisitionTermination, Never>?
    /// 現在の取得Taskの世代です。
    private var runningGeneration: UInt?
    /// flushに失敗した世代です。
    private var flushFailedGeneration: UInt?

    /// 取得境界、評価部品、方針、記録境界、clockを固定します。
    ///
    /// 責務: 応答駆動の取得ループの副作用境界を注入します。
    /// - Parameters:
    ///   - telemetry: PID単位のtyped Transport観測を返す取得境界。
    ///   - decoder: 正応答を評価する部品。
    ///   - pollingPolicy: 周回ごとの要求列を選ぶ方針。
    ///   - recorder: 受信結果を記録する境界。記録しない経路では `nil`。
    ///   - now: batch開始日時と表示用観測日時を供給するclock。
    ///   - clock: 要求ごとの経過と途切れを測る単調時計。
    ///   - linkRecovery: 途切れた後の回復操作の境界。
    ///   - deadlineWaiter: 一時停止中に猶予切れの期限まで待つ境界。
    init(
        telemetry: any OBDPIDTelemetryPort,
        decoder: OBDPIDPayloadDecoder = .init(),
        pollingPolicy: OBDPIDPollingPolicy = .init(),
        recorder: (any LiveTelemetryAcquisitionRecordingPort)?,
        now: @escaping @Sendable () -> Date = Date.init,
        clock: any MonotonicClockPort,
        linkRecovery: any LiveTelemetryLinkRecoveryPort,
        deadlineWaiter: any LiveTelemetryDeadlineWaitPort
    ) {
        reader = OBDPIDSingleRequestReader(telemetry: telemetry)
        self.telemetry = telemetry
        self.decoder = decoder
        self.pollingPolicy = pollingPolicy
        self.recorder = recorder
        self.now = now
        self.clock = clock
        recovery = LiveTelemetryAcquisitionRecovery(
            linkRecovery: linkRecovery,
            reader: reader,
            clock: clock,
            deadlineWaiter: deadlineWaiter
        )
        recordsAcquisition = recorder != nil
    }

    /// 新しい世代の取得を始め、その出来事のストリームを返します。
    ///
    /// 責務: 前の世代を取り消し、その終了後に新しい世代の取得Taskを始めます。
    /// ストリームの購読をやめると取得Taskを取り消します。
    /// - Parameter input: 世代、取得対象定義、capability、終端。
    /// - Returns: 取得対象の確定、数値化した観測、終了理由を流すストリーム。
    func start(_ input: LiveTelemetryAcquisitionLoopInput) -> AsyncStream<LiveTelemetryAcquisitionEvent> {
        let previous = runningTask
        previous?.cancel()
        let (stream, continuation) = AsyncStream.makeStream(of: LiveTelemetryAcquisitionEvent.self)
        runningGeneration = input.generation
        let task = Task { await self.run(input, after: previous, continuation: continuation) }
        continuation.onTermination = { _ in task.cancel() }
        runningTask = task
        return stream
    }

    /// 現在の世代の取得を止め、終わるまで待ちます。
    ///
    /// 責務: 取得Taskを取り消し、記録の終了と通信資源の解放を待って終了理由を返します。
    /// - Returns: 取得Taskの終了理由。動いていなかった場合は `nil`。
    func stop() async -> LiveTelemetryAcquisitionTermination? {
        guard let task = runningTask else { return nil }
        task.cancel()
        let termination = await task.value
        if runningTask == task {
            runningTask = nil
            runningGeneration = nil
        }
        return termination
    }

    /// 件数や経過にかかわらず保存待ちの記録を保存させます。
    ///
    /// 責務: 現在の世代の記録境界へflushを指示し、失敗を世代ごとに保持します。
    /// - Parameter trigger: 保存の契機。
    func flush(_ trigger: LiveTelemetryAcquisitionFlushTrigger) async {
        guard let recorder, let generation = runningGeneration else { return }
        do {
            try await recorder.flush(trigger, generation: generation)
        } catch {
            flushFailedGeneration = generation
        }
    }

    /// 取得ループの外から届いた、状態を判定し直す機会を伝えます。
    ///
    /// 責務: 一時停止中の取得Taskへ起床理由を渡します。一時停止していなければ何もしません。
    /// - Parameter signal: フォアグラウンド復帰・バックグラウンド移行・リンク状態の変化。
    func notify(_ signal: LiveTelemetryAcquisitionWakeSignal) {
        pauseChannel.send(.signal(signal))
    }

    /// 前の世代の終了を待ってから1世代の取得を行い、ストリームを閉じます。
    ///
    /// 責務: 1世代の取得Taskの本体として、取得・記録終了・資源解放・終了通知を順に行います。
    /// - Parameters:
    ///   - input: 世代、取得対象定義、capability、終端。
    ///   - previous: 終了を待つ前の世代の取得Task。
    ///   - continuation: 出来事を流すストリームの送出口。
    /// - Returns: 取得の終了理由。
    private func run(
        _ input: LiveTelemetryAcquisitionLoopInput,
        after previous: Task<LiveTelemetryAcquisitionTermination, Never>?,
        continuation: AsyncStream<LiveTelemetryAcquisitionEvent>.Continuation
    ) async -> LiveTelemetryAcquisitionTermination {
        _ = await previous?.value
        var termination: LiveTelemetryAcquisitionTermination
        do {
            try await startRecording(input)
            termination = try await acquire(input, continuation: continuation)
        } catch {
            termination = Task.isCancelled || error is CancellationError ? .stopped : .recordingFailed
        }
        termination = await finishRecording(generation: input.generation, termination: termination)
        await telemetry.endSession()
        if flushFailedGeneration == input.generation { flushFailedGeneration = nil }
        if runningGeneration == input.generation {
            runningTask = nil
            runningGeneration = nil
        }
        continuation.yield(.ended(termination))
        continuation.finish()
        return termination
    }

    /// 取得記録を開始します。
    ///
    /// 責務: manifestと区間を確定させ、記録しない経路では何もしません。
    /// - Parameter input: 世代、取得対象定義、capability、終端。
    /// - Throws: capabilityが定義と揃わない場合は `.invalidInput`、または記録境界の開始失敗。
    private func startRecording(_ input: LiveTelemetryAcquisitionLoopInput) async throws {
        guard let recorder else { return }
        guard input.capabilities.count == input.definitions.count else {
            throw LiveTelemetryAcquisitionRecordingError.invalidInput
        }
        try await recorder.start(
            LiveTelemetryAcquisitionStartInput(
                generation: input.generation,
                definitions: input.definitions,
                capabilities: input.capabilities,
                orderedRequests: pollingPolicy.definitionsToPoll(from: input.definitions, tick: 0).map {
                    OBDPIDRequest(service: $0.service, pid: $0.pid)
                }
            )
        )
    }

    /// 周回と回復を繰り返し、猶予切れになったところで止めます。
    ///
    /// 責務: 途切れるまで周回し、途切れたら区間を閉じて回復を任せ、復帰したら欠損を挟んで次の区間を開きます。
    /// - Parameters:
    ///   - input: 世代、取得対象定義、capability、終端。
    ///   - continuation: 出来事を流すストリームの送出口。
    /// - Returns: 猶予切れの終了理由。
    /// - Throws: 取消、または記録境界の失敗。
    private func acquire(
        _ input: LiveTelemetryAcquisitionLoopInput,
        continuation: AsyncStream<LiveTelemetryAcquisitionEvent>.Continuation
    ) async throws -> LiveTelemetryAcquisitionTermination {
        var cursor = LiveTelemetryPollingCursor(definitions: input.definitions)
        var tracker = LiveTelemetryReceiveTracker(startedNanoseconds: clock.nowNanoseconds(), startedAt: now())
        while true {
            let cause = try await pollUntilInterrupted(&cursor, tracker: &tracker, input: input, continuation: continuation)
            try await recorder?.endSegment(
                generation: input.generation,
                reason: cause.segmentEndReason,
                lastReceivedAt: tracker.lastReceivedAt
            )
            let outcome = try await recovery.recover(
                from: cause,
                probe: pollingPolicy.definitionsToPoll(from: cursor.targets, tick: 0).first,
                endpoint: input.endpoint,
                channel: pauseChannel,
                report: { continuation.yield(.phaseChanged($0)) }
            )
            guard case let .resumed(startReason) = outcome else {
                return .gracePeriodExpired(cause: cause, lastReceivedAt: tracker.lastReceivedAt)
            }
            try await recorder?.beginSegment(
                LiveTelemetryAcquisitionSegmentResumption(
                    generation: input.generation,
                    startReason: startReason,
                    gapCause: cause.gapCause,
                    gapStartedAt: tracker.lastReceivedAt
                )
            )
            tracker.restart(atNanoseconds: clock.nowNanoseconds(), at: now())
            continuation.yield(.phaseChanged(.acquiring))
        }
    }

    /// 取得が途切れるまで周回を繰り返します。
    ///
    /// 責務: 周回番号とbatch番号を進め、正応答のあった最初の周回で以後の取得対象を確定します。
    /// - Parameters:
    ///   - cursor: 取得対象・周回番号・batch番号。
    ///   - tracker: 最後の受信と途切れの判定。
    ///   - input: 世代、取得対象定義、capability、終端。
    ///   - continuation: 出来事を流すストリームの送出口。
    /// - Returns: 途切れの原因。
    /// - Throws: 取消、または記録境界の失敗。
    private func pollUntilInterrupted(
        _ cursor: inout LiveTelemetryPollingCursor,
        tracker: inout LiveTelemetryReceiveTracker,
        input: LiveTelemetryAcquisitionLoopInput,
        continuation: AsyncStream<LiveTelemetryAcquisitionEvent>.Continuation
    ) async throws -> LiveTelemetryInterruptionCause {
        while true {
            try Task.checkCancellation()
            let round = pollingPolicy.definitionsToPoll(from: cursor.targets, tick: cursor.tick)
            let result = try await pollRound(round, cursor: cursor, tracker: &tracker, input: input, continuation: continuation)
            switch result {
            case let .interrupted(cause):
                cursor.abandonRound()
                return cause
            case let .completed(outcome):
                if let confirmed = cursor.advance(after: outcome) {
                    continuation.yield(.targetsConfirmed(pollingPolicy.definitionsToPoll(from: confirmed, tick: 0)))
                }
            }
        }
    }

    /// 1周回の要求を1件ずつ送り、結果を記録して観測を流します。
    ///
    /// 責務: 前の要求の結果を受けてから次の要求を送り、結果を受けるたびに途切れを判定します。
    /// - Parameters:
    ///   - round: 今周回で送る順序付き定義。
    ///   - cursor: 周回番号とbatch番号。
    ///   - tracker: 最後の受信と途切れの判定。
    ///   - input: 世代と終端を含む開始入力。
    ///   - continuation: 出来事を流すストリームの送出口。
    /// - Returns: 周回を送り終えた集計、または途中で途切れた原因。
    /// - Throws: 取消、または記録境界の失敗。
    private func pollRound(
        _ round: [OBDPIDDefinition],
        cursor: LiveTelemetryPollingCursor,
        tracker: inout LiveTelemetryReceiveTracker,
        input: LiveTelemetryAcquisitionLoopInput,
        continuation: AsyncStream<LiveTelemetryAcquisitionEvent>.Continuation
    ) async throws -> LiveTelemetryRoundResult {
        let requests = round.map { OBDPIDRequest(service: $0.service, pid: $0.pid) }
        try await recorder?.beginRound(
            LiveTelemetryAcquisitionRoundInput(
                generation: input.generation,
                batchOrdinal: cursor.batchOrdinal,
                policyTick: cursor.tick,
                startedAt: now(),
                requests: requests
            )
        )
        var outcome = LiveTelemetryRoundOutcome()
        for (ordinal, definition) in round.enumerated() {
            try Task.checkCancellation()
            let transport = try await exchange(
                definition,
                requestOrdinal: ordinal,
                batchOrdinal: cursor.batchOrdinal,
                input: input,
                continuation: continuation
            )
            if transport == .cancelled { throw CancellationError() }
            outcome.add(transport, for: requests[ordinal])
            tracker.observe(transport, atNanoseconds: clock.nowNanoseconds(), at: now())
            if let cause = tracker.interruption(nowNanoseconds: clock.nowNanoseconds()) { return .interrupted(cause) }
        }
        try await recorder?.finishRound(generation: input.generation, batchOrdinal: cursor.batchOrdinal)
        return .completed(outcome)
    }

    /// 1件の要求を送り、結果を記録して数値化できた観測を流します。
    ///
    /// 責務: 1要求の送信・受信・評価・記録・観測送出を行います。
    /// - Parameters:
    ///   - definition: 送る取得時PID定義。
    ///   - requestOrdinal: 周回内の要求順。
    ///   - batchOrdinal: セッション内のbatch番号。
    ///   - input: 世代と終端を含む開始入力。
    ///   - continuation: 出来事を流すストリームの送出口。
    /// - Returns: 要求のTransport観測。
    /// - Throws: 記録境界の失敗、またはflush失敗による `.storageFailed`。
    private func exchange(
        _ definition: OBDPIDDefinition,
        requestOrdinal: Int,
        batchOrdinal: Int64,
        input: LiveTelemetryAcquisitionLoopInput,
        continuation: AsyncStream<LiveTelemetryAcquisitionEvent>.Continuation
    ) async throws -> OBDPIDRequestTransportOutcome {
        let started = clock.nowNanoseconds()
        let transport = await reader.read(definition, using: input.endpoint)
        let ended = clock.nowNanoseconds()
        var decoding: OBDPIDPayloadDecoding?
        if case let .responded(payload) = transport {
            decoding = decoder.decode(payload, definition: definition, observedAt: now())
        }
        try await recorder?.record(
            LiveTelemetryRequestResult(
                generation: input.generation,
                batchOrdinal: batchOrdinal,
                requestOrdinal: requestOrdinal,
                request: OBDPIDRequest(service: definition.service, pid: definition.pid),
                outcome: transport,
                valueOutcome: decoding?.valueOutcome ?? .notEvaluated,
                elapsedNanoseconds: ended >= started ? ended - started : 0
            )
        )
        if let sample = decoding?.sample { continuation.yield(.sampleDecoded(sample)) }
        guard flushFailedGeneration != input.generation else {
            throw LiveTelemetryAcquisitionRecordingError.storageFailed
        }
        return transport
    }

    /// 取得記録を終え、記録の失敗を終了理由へ反映します。
    ///
    /// 責務: 記録境界へ終了を伝え、終了処理の失敗を保存失敗として扱います。
    /// - Parameters:
    ///   - generation: 終える世代。
    ///   - termination: 取得側で決まった終了理由。
    /// - Returns: 記録の終了に失敗した場合は `.recordingFailed`、それ以外は `termination`。
    private func finishRecording(
        generation: UInt,
        termination: LiveTelemetryAcquisitionTermination
    ) async -> LiveTelemetryAcquisitionTermination {
        guard let recorder else { return termination }
        do {
            try await recorder.finish(generation: generation, reason: termination.sessionEndReason)
            return termination
        } catch {
            return .recordingFailed
        }
    }
}
