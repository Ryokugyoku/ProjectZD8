import Foundation

/// PID要求を1件ずつ送り、結果を受けた処理の中で次の1件を送る応答駆動の取得ループです。
///
/// 要求の間に待機を挟みません。1周回を1 batchとし、周回の全要求が終わると周回番号を進めて
/// `OBDPIDPollingPolicy` で次の周回の要求列を選びます。初回周回で正応答を返したPIDだけを以後の対象にします。
/// 取得対象は開始時に渡された定義(車両別の収集トグルが有効なPIDだけ)の部分集合で、ループが要求を足すことはありません。
///
/// actor再入の方針:
/// - 取得処理は1世代につき1つのTaskで直列に進みます。要求の送信・記録・周回の切替は同じTask内の
///   `await` の連鎖なので、互いに追い越しません。
/// - `start` は前の世代のTaskを取り消し、新しいTaskは前のTaskの終了(記録の終了と通信資源の解放)を
///   待ってから始まります。`stop` も取消後にTaskの終了を待ちます。どちらも、待っている間に別の
///   `start` が来た場合に備え、保持しているTaskが入れ替わっていないかを確かめてから状態を片付けます。
/// - `flush` は取得Taskの要求待ちの間に実行され得ます。記録先は同じactorで直列に処理し、未完了の周回は
///   次のチャンクへ持ち越すため、取得Taskの前提を崩しません。失敗は世代ごとに記録し、取得Taskが次の受信後に
///   保存失敗として終了します。
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
    /// 要求ごとの経過を測る単調時計です。
    private let clock: any MonotonicClockPort
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
    ///   - clock: 要求ごとの経過を測る単調時計。
    init(
        telemetry: any OBDPIDTelemetryPort,
        decoder: OBDPIDPayloadDecoder = .init(),
        pollingPolicy: OBDPIDPollingPolicy = .init(),
        recorder: (any LiveTelemetryAcquisitionRecordingPort)?,
        now: @escaping @Sendable () -> Date = Date.init,
        clock: any MonotonicClockPort
    ) {
        reader = OBDPIDSingleRequestReader(telemetry: telemetry)
        self.telemetry = telemetry
        self.decoder = decoder
        self.pollingPolicy = pollingPolicy
        self.recorder = recorder
        self.now = now
        self.clock = clock
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
            termination = try await pollRounds(input, continuation: continuation)
        } catch {
            termination = Task.isCancelled ? .stopped : .recordingFailed
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

    /// 周回を繰り返し、終了理由が出たところで止めます。
    ///
    /// 責務: 周回番号とbatch番号を進め、初回周回の応答から以後の取得対象を確定します。
    /// - Parameters:
    ///   - input: 世代、取得対象定義、capability、終端。
    ///   - continuation: 出来事を流すストリームの送出口。
    /// - Returns: 周回の集計から得た終了理由。
    /// - Throws: 取消、または記録境界の失敗。
    private func pollRounds(
        _ input: LiveTelemetryAcquisitionLoopInput,
        continuation: AsyncStream<LiveTelemetryAcquisitionEvent>.Continuation
    ) async throws -> LiveTelemetryAcquisitionTermination {
        var targets = input.definitions
        var tick: UInt = 0
        var batchOrdinal: Int64 = 0
        while true {
            try Task.checkCancellation()
            let round = pollingPolicy.definitionsToPoll(from: targets, tick: tick)
            let outcome = try await pollRound(
                round,
                tick: tick,
                batchOrdinal: batchOrdinal,
                input: input,
                continuation: continuation
            )
            if let termination = outcome.termination { return termination }
            if tick == 0 {
                let responded = Set(outcome.respondedRequests)
                targets = targets.filter { responded.contains(OBDPIDRequest(service: $0.service, pid: $0.pid)) }
                continuation.yield(.targetsConfirmed(pollingPolicy.definitionsToPoll(from: targets, tick: 0)))
            }
            tick &+= 1
            batchOrdinal += 1
        }
    }

    /// 1周回の要求を1件ずつ送り、結果を記録して観測を流します。
    ///
    /// 責務: 前の要求の結果を受けてから次の要求を送り、1周回を1 batchとして記録します。
    /// - Parameters:
    ///   - round: 今周回で送る順序付き定義。
    ///   - tick: polling policyの周回番号。
    ///   - batchOrdinal: セッション内のbatch番号。
    ///   - input: 世代と終端を含む開始入力。
    ///   - continuation: 出来事を流すストリームの送出口。
    /// - Returns: 今周回の要求結果の集計。
    /// - Throws: 取消、または記録境界の失敗。
    private func pollRound(
        _ round: [OBDPIDDefinition],
        tick: UInt,
        batchOrdinal: Int64,
        input: LiveTelemetryAcquisitionLoopInput,
        continuation: AsyncStream<LiveTelemetryAcquisitionEvent>.Continuation
    ) async throws -> LiveTelemetryRoundOutcome {
        let requests = round.map { OBDPIDRequest(service: $0.service, pid: $0.pid) }
        try await recorder?.beginRound(
            LiveTelemetryAcquisitionRoundInput(
                generation: input.generation,
                batchOrdinal: batchOrdinal,
                policyTick: tick,
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
                batchOrdinal: batchOrdinal,
                input: input,
                continuation: continuation
            )
            outcome.add(transport, for: requests[ordinal])
            if transport == .cancelled { return outcome }
        }
        try await recorder?.finishRound(generation: input.generation, batchOrdinal: batchOrdinal)
        return outcome
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
