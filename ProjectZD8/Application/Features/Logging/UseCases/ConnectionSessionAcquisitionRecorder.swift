import Foundation

/// LiveTelemetryの取得ループから受けた要求結果をメモリ上に積み、チャンク単位で保存します。
///
/// actor再入の方針:
/// - commit・欠損記録・区間の保存は同期呼び出しで、途中に `await` を挟みません。commit中に届いた
///   受信はactorの順番待ちになり、commitが終わってからバッファへ積まれます。flushと通常のcommitも
///   同じ理由で交互に実行され、同じチャンクを二重に組み立てません。
/// - `await` をまたぐのは `start` だけです。`start` は再開後に世代が現在のままかを確かめ、
///   途中で `finish` や別世代の `start` が来ていれば記録状態を作らずに失敗します。
/// - `finish` は記録状態を同期的に片付けてから最後に `await` するため、後続の `start` と状態を共有しません。
/// - 区間の切替(`endSegment` / `beginSegment` / `switchMode`)も同期処理だけで、途中に `await` を挟みません。
///   flushと区間の切替は交互に実行され、`endSegment` は未完了batchの打切りと残りのcommitを済ませてから区間を閉じるため、
///   閉じた区間へ後からRawが入ることはありません。区間が閉じている間のflushは保存するものが無く何もしません。
actor ConnectionSessionAcquisitionRecorder: LiveTelemetryAcquisitionRecordingPort {
    /// manifestと開始境界を原子的に保存するuse caseです。
    private let createManifest: CreateConnectionSessionAcquisitionManifestUseCase
    /// Rawと取得証跡をチャンク単位で保存する境界です。
    private let chunkRepository: any ConnectionSessionAcquisitionChunkRepository
    /// 区間開始と欠損番号の続きを求める部品です。
    private let segmentOpener: AcquisitionSegmentOpener
    /// 取得中の区間を閉じ、欠損を挟んで次の区間を開く部品です。
    private let segmentSwitcher: AcquisitionSegmentSwitcher
    /// 破棄したチャンクを欠損として記録する部品です。
    private let lossRecorder: AcquisitionChunkLossRecorder
    /// セッションに保存済みのRawの次の記録順序を返す境界です。
    private let nextRawSequence: @Sendable (ConnectionSessionID) async throws -> Int64
    /// セッションに保存済みのbatchの次のbatch番号を返す境界です。
    private let nextBatchOrdinal: @Sendable (ConnectionSessionID) async throws -> Int64
    /// 現在Logging sessionの識別子を返す境界です。
    private let activeSessionID: @Sendable () async -> ConnectionSessionID?
    /// manifestへ記録する取得契約のversion一式です。
    private let versions: AcquisitionManifestVersions
    /// Raw観測日時とbatch時刻を供給するclockです。
    private let now: @Sendable () -> Date
    /// Rawの単調時刻とcommit経過を測る単調時計です。
    private let clock: any MonotonicClockPort
    /// 件数と経過からcommit要否を決める方針です。
    private let commitPolicy: AcquisitionChunkCommitPolicy
    /// Transport観測をrequest結果へ分類する部品です。
    private let classifier: AcquisitionTransportOutcomeClassifier
    /// 取得開始と世代終了の匿名性能event通知先です。
    private let performanceEvents: any AcquisitionPerformanceEventPort
    /// 記録を受け付ける世代です。開始中も含みます。
    private var activeGeneration: UInt?
    /// 開始が完了した世代の記録状態です。
    private var session: AcquisitionRecordingSession?
    /// 保存待ちのRawと取得証跡です。
    private var buffer = AcquisitionChunkBuffer(nextSequence: 0)
    /// 保存も欠損記録もできず、記録を続けられない状態かどうかです。
    private var hasStorageFailed = false

    /// 保存先、clock、方針を固定します。
    ///
    /// 責務: 取得記録workflowの副作用境界を注入します。
    /// - Parameters:
    ///   - createManifest: manifestと開始境界を原子的に保存するuse case。
    ///   - chunkRepository: Rawと取得証跡をチャンク単位で保存する境界。
    ///   - segmentRepository: 連続取得区間を保存する境界。
    ///   - gapRepository: 欠損を保存する境界。
    ///   - nextRawSequence: セッションに保存済みのRawの次の記録順序を返す境界。
    ///   - nextBatchOrdinal: セッションに保存済みのbatchの次のbatch番号を返す境界。省略時は常に0。
    ///   - activeSessionID: 現在Logging sessionの識別子を返す境界。
    ///   - versions: manifestへ記録する取得契約のversion一式。
    ///   - now: Raw観測日時とbatch時刻を供給するclock。
    ///   - clock: Rawの単調時刻とcommit経過を測る単調時計。
    ///   - commitPolicy: 件数と経過からcommit要否を決める方針。
    ///   - performanceEvents: 取得開始と世代終了の匿名性能event通知先。
    init(
        createManifest: CreateConnectionSessionAcquisitionManifestUseCase,
        chunkRepository: any ConnectionSessionAcquisitionChunkRepository,
        segmentRepository: any ConnectionSessionSegmentRepository,
        gapRepository: any ConnectionSessionGapRepository,
        nextRawSequence: @escaping @Sendable (ConnectionSessionID) async throws -> Int64,
        nextBatchOrdinal: @escaping @Sendable (ConnectionSessionID) async throws -> Int64 = { _ in 0 },
        activeSessionID: @escaping @Sendable () async -> ConnectionSessionID?,
        versions: AcquisitionManifestVersions,
        now: @escaping @Sendable () -> Date = Date.init,
        clock: any MonotonicClockPort,
        commitPolicy: AcquisitionChunkCommitPolicy = .init(),
        performanceEvents: any AcquisitionPerformanceEventPort = NoOpAcquisitionPerformanceEventPort()
    ) {
        self.createManifest = createManifest
        self.chunkRepository = chunkRepository
        segmentOpener = AcquisitionSegmentOpener(segmentRepository: segmentRepository, gapRepository: gapRepository)
        segmentSwitcher = AcquisitionSegmentSwitcher(segmentRepository: segmentRepository, gapRepository: gapRepository)
        lossRecorder = AcquisitionChunkLossRecorder(gapRepository: gapRepository)
        self.nextRawSequence = nextRawSequence
        self.nextBatchOrdinal = nextBatchOrdinal
        self.activeSessionID = activeSessionID
        self.versions = versions
        self.now = now
        self.clock = clock
        self.commitPolicy = commitPolicy
        classifier = AcquisitionTransportOutcomeClassifier()
        self.performanceEvents = performanceEvents
    }

    /// manifestを確定し、セッションの連続取得区間を開始します。
    ///
    /// 責務: 1世代のmanifest保存と区間開始を終えてから記録を受け付け可能にします。
    /// - Parameter input: 定義、capability、基準要求順を含む取得開始入力。
    /// - Throws: セッション不在、入力不正、世代の入替、または保存失敗。
    func start(_ input: LiveTelemetryAcquisitionStartInput) async throws {
        let generation = input.generation
        let interval = performanceEvents.begin(.acquisitionStart, context: AcquisitionPerformanceContext(generation: generation))
        activeGeneration = generation
        session = nil
        hasStorageFailed = false
        do {
            guard let sessionID = await activeSessionID() else { throw ConnectionSessionRepositoryError.invalidState }
            await createManifest.activate(generation: generation)
            let permission = try await createManifest.execute(manifestInput(input, sessionID: sessionID))
            let firstSequence = try await nextRawSequence(sessionID)
            let batchOrdinalBase = try await nextBatchOrdinal(sessionID)
            try ensureActive(generation)
            try openSession(permission: permission, firstSequence: firstSequence, batchOrdinalBase: batchOrdinalBase)
            performanceEvents.end(interval, outcome: .succeeded)
        } catch {
            if activeGeneration == generation { activeGeneration = nil }
            await createManifest.cancel(generation: generation)
            performanceEvents.end(interval, outcome: .failed)
            throw error
        }
    }

    /// 1周回(1 batch)の開始を記録します。
    ///
    /// 責務: 周回の要求列をmanifest位置へ対応付け、未完了batchとしてバッファへ積みます。
    /// - Parameter input: 周回の識別子と要求列。
    /// - Throws: 世代不一致、manifestに無い要求、重複要求、未完了batchの残存、または記録不能状態。
    func beginRound(_ input: LiveTelemetryAcquisitionRoundInput) async throws {
        let session = try openSegmentSession(input.generation)
        let ordinals = try input.requests.map { request in
            guard let ordinal = session.manifestOrdinalByRequest[request] else {
                throw LiveTelemetryAcquisitionRecordingError.invalidInput
            }
            return ordinal
        }
        guard Set(ordinals).count == ordinals.count, !ordinals.isEmpty else {
            throw LiveTelemetryAcquisitionRecordingError.invalidInput
        }
        try buffer.begin(
            AcquisitionBufferedBatch(
                identity: try AcquisitionBatchIdentity(ordinal: session.storedBatchOrdinal(input.batchOrdinal)),
                generation: input.generation,
                policyTick: input.policyTick,
                startedAt: input.startedAt,
                manifestPIDOrdinals: ordinals
            )
        )
    }

    /// 要求1件の結果を記録します。
    ///
    /// 責務: 結果をバッファへ積み、正応答には実時刻・単調時刻・区間番号を付け、commit要否を判定します。
    /// - Parameter result: 要求1件の結果。
    /// - Throws: 世代不一致、順序不正、または保存も欠損記録もできない場合。
    func record(_ result: LiveTelemetryRequestResult) async throws {
        var session = try openSegmentSession(result.generation)
        guard let manifestOrdinal = session.manifestOrdinalByRequest[result.request] else {
            throw LiveTelemetryAcquisitionRecordingError.invalidInput
        }
        let classified = classifier.classify(result.outcome)
        var raw: AcquisitionBufferedRaw?
        if case let .responded(payload) = result.outcome {
            raw = AcquisitionBufferedRaw(
                observedAt: now(),
                monotonicNanoseconds: session.stamp(clock.nowNanoseconds()),
                segmentOrdinal: session.segmentOrdinal,
                elapsedNanoseconds: result.elapsedNanoseconds,
                request: result.request,
                payload: payload
            )
        }
        try buffer.updateOpenBatch(ordinal: session.storedBatchOrdinal(result.batchOrdinal)) { batch in
            guard batch.requests.indices.contains(result.requestOrdinal),
                  batch.requests[result.requestOrdinal].manifestPIDOrdinal == manifestOrdinal else {
                throw LiveTelemetryAcquisitionRecordingError.invalidInput
            }
            try batch.record(
                requestOrdinal: result.requestOrdinal,
                transportOutcome: classified.transportOutcome,
                valueOutcome: classified.transportOutcome == .responded ? result.valueOutcome : .notEvaluated,
                elapsedNanoseconds: result.elapsedNanoseconds,
                reasonCode: classified.reasonCode,
                raw: raw
            )
        }
        self.session = session
        try commitIfDue()
    }

    /// 1周回の全要求が終わったことを記録します。
    ///
    /// 責務: 未完了batchを終端状態へ確定し、commit要否を判定します。
    /// - Parameters:
    ///   - generation: 取得ループが所有する世代。
    ///   - batchOrdinal: 終える周回のbatch番号。
    /// - Throws: 世代不一致、未終了要求の残存、または保存も欠損記録もできない場合。
    func finishRound(generation: UInt, batchOrdinal: Int64) async throws {
        let session = try openSegmentSession(generation)
        let completedAt = now()
        try buffer.updateOpenBatch(ordinal: session.storedBatchOrdinal(batchOrdinal)) { batch in
            try batch.complete(at: completedAt, classifier: classifier)
        }
        try commitIfDue()
    }

    /// 件数や経過時間にかかわらず、終端済みの記録をすべて保存します。
    ///
    /// 責務: 指定契機で保存可能なチャンクを1回commitします。未完了batchは次のチャンクへ持ち越します。
    /// - Parameters:
    ///   - trigger: 保存の契機。
    ///   - generation: 取得ループが所有する世代。開始前・終了後の世代では何もしません。
    /// - Throws: 保存も欠損記録もできない場合。
    func flush(_ trigger: LiveTelemetryAcquisitionFlushTrigger, generation: UInt) async throws {
        guard activeGeneration == generation, session?.generation == generation else { return }
        guard !hasStorageFailed else { throw LiveTelemetryAcquisitionRecordingError.storageFailed }
        try commitPending()
    }

    /// 取得が途切れたため、現在の連続取得区間を閉じます。
    ///
    /// 責務: 未完了batchを打ち切って保存待ちの記録をcommitし(flush契機 `segmentEnded`)、区間を指定原因で終了します。
    /// - Parameters:
    ///   - generation: 取得ループが所有する世代。
    ///   - reason: 区間が終わった直接原因。
    ///   - lastReceivedAt: 最後に正応答を受信した実時間。区間の終了時刻に使います。
    /// - Throws: 世代不一致・区間が閉じている場合は `.inactiveGeneration` / `.invalidInput`、保存できない場合は `.storageFailed`。
    func endSegment(generation: UInt, reason: ConnectionSessionSegmentEndReason, lastReceivedAt: Date) async throws {
        _ = try openSegmentSession(generation)
        try closeCurrentSegment(endedAt: lastReceivedAt, reason: reason)
    }

    /// 途絶から復帰したため、欠損を挟んで次の連続取得区間を開きます。
    ///
    /// 責務: 欠損と次の区間を保存し、Rawの記録順序と単調時計の起点を新しい区間へ切り替えます。
    /// - Parameter input: 世代、開始理由、欠損の原因と開始時刻。
    /// - Throws: 世代不一致は `.inactiveGeneration`、区間が開いたままなら `.invalidInput`、保存できない場合は `.storageFailed`。
    func beginSegment(_ input: LiveTelemetryAcquisitionSegmentResumption) async throws {
        var session = try activeSession(input.generation)
        guard !session.isSegmentOpen else { throw LiveTelemetryAcquisitionRecordingError.invalidInput }
        let gap = AcquisitionSegmentSwitcher.Gap(
            ordinal: session.takeGapOrdinal(),
            startedAt: input.gapStartedAt,
            cause: input.gapCause
        )
        try openNextSegment(&session, startReason: input.startReason, gap: gap)
    }

    /// 取得モードの切替のため、現在の区間を閉じて次の区間を開きます。
    ///
    /// 責務: 保存待ちの記録をcommitして区間を `modeSwitched` で終了し、欠損なしで `modeSwitched` の区間を開始します。
    /// 欠損原因にモード切替が無い(DBのCHECK制約で許されない)ため、欠損は記録しません。
    /// - Parameter generation: 取得ループが所有する世代。
    /// - Throws: 世代不一致・区間が閉じている場合、または保存できない場合。
    func switchMode(generation: UInt) async throws {
        _ = try openSegmentSession(generation)
        try closeCurrentSegment(endedAt: now(), reason: .modeSwitched)
        guard var session else { throw LiveTelemetryAcquisitionRecordingError.inactiveGeneration }
        try openNextSegment(&session, startReason: .modeSwitched, gap: nil)
    }

    /// 取得を終え、保存待ちの記録と連続取得区間を閉じます。
    ///
    /// 責務: 未完了batchを打ち切って残りをcommitし、区間を終了して記録状態を片付けます。
    /// - Parameters:
    ///   - generation: 終える世代。現在の世代でなければ何もしません。
    ///   - reason: 取得が終わった直接原因。
    /// - Throws: 保存も欠損記録もできなかった場合、または区間を終了できない場合は `.storageFailed`。
    func finish(generation: UInt, reason: ConnectionSessionEndReason) async throws {
        guard activeGeneration == generation else { return }
        let interval = performanceEvents.begin(.generationCancellation, context: AcquisitionPerformanceContext(generation: generation))
        activeGeneration = nil
        var failed = hasStorageFailed
        if let session {
            failed = !closeSession(session, reason: reason) || failed
        }
        session = nil
        buffer = AcquisitionChunkBuffer(nextSequence: 0)
        hasStorageFailed = false
        await createManifest.cancel(generation: generation)
        performanceEvents.end(interval, outcome: failed ? .failed : .succeeded)
        if failed { throw LiveTelemetryAcquisitionRecordingError.storageFailed }
    }

    /// 取得開始入力をmanifest作成入力へ変換します。
    ///
    /// 責務: 開始入力とversion一式を1件のmanifest作成入力へまとめます。
    /// - Parameters:
    ///   - input: 定義、capability、基準要求順を含む取得開始入力。
    ///   - sessionID: manifestを所有する接続セッション。
    /// - Returns: manifest作成入力。
    private func manifestInput(
        _ input: LiveTelemetryAcquisitionStartInput,
        sessionID: ConnectionSessionID
    ) -> CreateConnectionSessionAcquisitionManifestInput {
        CreateConnectionSessionAcquisitionManifestInput(
            sessionID: sessionID,
            generation: input.generation,
            manifestVersion: versions.manifestVersion,
            pollingPolicyVersion: versions.pollingPolicyVersion,
            modelInputManifestVersion: versions.modelInputManifestVersion,
            formulaCanonicalizationVersion: versions.formulaCanonicalizationVersion,
            pidDefinitions: input.definitions,
            pidCapabilities: input.capabilities,
            orderedRequestedPIDs: input.orderedRequests
        )
    }

    /// 区間を開始して記録状態を作ります。
    ///
    /// 責務: manifest保存済みの許可から区間を開始し、記録状態と空のバッファを用意します。
    /// - Parameters:
    ///   - permission: manifestとRaw開始境界の保存済み許可。
    ///   - firstSequence: 新しい区間の最初の行へ割り当てる記録順序。
    ///   - batchOrdinalBase: セッションに保存済みのbatchの次のbatch番号。
    /// - Throws: manifestに要求順が無い場合は `.invalidInput`、区間の保存に失敗した場合の保存先エラー。
    private func openSession(
        permission: ConnectionSessionRawAcquisitionPermission,
        firstSequence: Int64,
        batchOrdinalBase: Int64
    ) throws {
        guard let ordered = permission.manifest.orderedRequestedPIDs else {
            throw LiveTelemetryAcquisitionRecordingError.invalidInput
        }
        let anchor = clock.nowNanoseconds()
        let startedAt = now()
        let opened = try segmentOpener.open(
            for: permission.sessionID,
            firstSequence: firstSequence,
            startedAt: startedAt,
            monotonicAnchorNanoseconds: anchor
        )
        session = AcquisitionRecordingSession(
            sessionID: permission.sessionID,
            generation: permission.generation,
            orderedRequests: ordered.requests,
            segmentOrdinal: opened.segmentOrdinal,
            segmentFirstSequence: firstSequence,
            segmentStartedAt: startedAt,
            nextGapOrdinal: opened.nextGapOrdinal,
            anchorNanoseconds: anchor,
            batchOrdinalBase: batchOrdinalBase
        )
        buffer = AcquisitionChunkBuffer(nextSequence: firstSequence)
    }

    /// 開始済みで記録を続けられる世代の記録状態を返します。
    ///
    /// 責務: 世代と記録可否を確かめて現在の記録状態を返します。
    /// - Parameter generation: 呼び出し側の世代。
    /// - Returns: 現在の記録状態。
    /// - Throws: 世代不一致・開始未完了は `.inactiveGeneration`、記録不能状態は `.storageFailed`。
    private func activeSession(_ generation: UInt) throws -> AcquisitionRecordingSession {
        guard activeGeneration == generation, let session, session.generation == generation else {
            throw LiveTelemetryAcquisitionRecordingError.inactiveGeneration
        }
        guard !hasStorageFailed else { throw LiveTelemetryAcquisitionRecordingError.storageFailed }
        return session
    }

    /// 区間が開いていて受信を記録できる世代の記録状態を返します。
    ///
    /// 責務: 世代・記録可否に加えて、途絶中(区間が閉じている間)の記録を拒否します。
    /// - Parameter generation: 呼び出し側の世代。
    /// - Returns: 現在の記録状態。
    /// - Throws: 世代不一致は `.inactiveGeneration`、区間が閉じている場合は `.invalidInput`、記録不能状態は `.storageFailed`。
    private func openSegmentSession(_ generation: UInt) throws -> AcquisitionRecordingSession {
        let session = try activeSession(generation)
        guard session.isSegmentOpen else { throw LiveTelemetryAcquisitionRecordingError.invalidInput }
        return session
    }

    /// 未完了batchを打ち切って保存待ちをcommitし、現在の区間を閉じます。
    ///
    /// 責務: 区間を閉じる前のflushと区間終了を途中に `await` を挟まず行い、失敗を記録不能状態へ反映します。
    /// - Parameters:
    ///   - endedAt: 区間を閉じる実時間の候補。
    ///   - reason: 区間が終わった直接原因。
    /// - Throws: 保存も欠損記録もできない場合、または区間を終了できない場合は `.storageFailed`。
    private func closeCurrentSegment(endedAt: Date, reason: ConnectionSessionSegmentEndReason) throws {
        buffer.abandonOpenBatch(at: now(), classifier: classifier)
        try commitPending()
        guard var session else { throw LiveTelemetryAcquisitionRecordingError.inactiveGeneration }
        do {
            try segmentSwitcher.close(
                session,
                endedAt: endedAt,
                reason: reason,
                lastCommittedSequence: buffer.lastCommittedSequence
            )
        } catch {
            hasStorageFailed = true
            throw LiveTelemetryAcquisitionRecordingError.storageFailed
        }
        session.closeSegment()
        self.session = session
    }

    /// 閉じた区間の続きとして次の区間を開き、記録状態を切り替えます。
    ///
    /// 責務: 欠損と区間の保存に成功した時だけ記録状態を新しい区間へ進め、失敗を記録不能状態へ反映します。
    /// - Parameters:
    ///   - session: 直前の区間を閉じた記録状態。欠損番号の払い出し後の値。
    ///   - startReason: 次の区間が始まった直接原因。
    ///   - gap: 区間の間に挟む欠損。記録しない切替では `nil`。
    /// - Throws: 欠損または区間を保存できない場合は `.storageFailed`。
    private func openNextSegment(
        _ session: inout AcquisitionRecordingSession,
        startReason: ConnectionSessionSegmentStartReason,
        gap: AcquisitionSegmentSwitcher.Gap?
    ) throws {
        let anchor = clock.nowNanoseconds()
        let startedAt = now()
        let firstSequence = buffer.nextSequence
        do {
            let ordinal = try segmentSwitcher.open(
                after: session,
                startReason: startReason,
                startedAt: startedAt,
                anchorNanoseconds: anchor,
                firstSequence: firstSequence,
                gap: gap
            )
            session.openSegment(ordinal: ordinal, firstSequence: firstSequence, startedAt: startedAt, anchorNanoseconds: anchor)
            self.session = session
        } catch {
            self.session = session
            hasStorageFailed = true
            throw LiveTelemetryAcquisitionRecordingError.storageFailed
        }
    }

    /// 開始中の世代が入れ替わっていないことを確かめます。
    ///
    /// 責務: `await` 後に世代の前提が崩れていれば記録状態を作らせません。
    /// - Parameter generation: 開始中の世代。
    /// - Throws: 世代が入れ替わった場合は `.inactiveGeneration`。
    private func ensureActive(_ generation: UInt) throws {
        guard activeGeneration == generation else { throw LiveTelemetryAcquisitionRecordingError.inactiveGeneration }
    }

    /// 件数と経過からcommit要否を判定し、必要ならcommitします。
    ///
    /// 責務: 受信のたびに単調時計で直近commitからの経過を測り、方針が求める時だけcommitします。
    /// - Throws: 保存も欠損記録もできない場合は `.storageFailed`。
    private func commitIfDue() throws {
        guard let session else { return }
        let terminalCount = buffer.batches.prefix { $0.isTerminal }.count
        let elapsed = session.elapsedSinceLastCommit(at: clock.nowNanoseconds())
        guard commitPolicy.shouldCommit(
            bufferedCount: buffer.bufferedRawCount + terminalCount,
            elapsedSinceLastCommitNanoseconds: elapsed
        ) else { return }
        try commitPending()
    }

    /// 終端済みの記録を1件のチャンクとしてcommitします。
    ///
    /// 責務: チャンクを1回だけ保存し、失敗時は再送せずに破棄して欠損を記録します。
    /// - Throws: 欠損も記録できない場合は `.storageFailed`。
    private func commitPending() throws {
        guard var session else { return }
        let pending: AcquisitionPendingChunk?
        do {
            pending = try buffer.pendingChunk(sessionID: session.sessionID)
        } catch {
            hasStorageFailed = true
            throw LiveTelemetryAcquisitionRecordingError.storageFailed
        }
        guard let pending else { return }
        session.markCommitAttempt(at: clock.nowNanoseconds())
        do {
            try chunkRepository.commit(pending.chunk)
            buffer.removeCommitted(pending)
        } catch {
            buffer.removeDiscarded(pending)
            do {
                try lossRecorder.recordLoss(
                    of: pending,
                    gapOrdinal: session.takeGapOrdinal(),
                    currentSegmentOrdinal: session.segmentOrdinal,
                    for: session.sessionID
                )
            } catch {
                self.session = session
                hasStorageFailed = true
                throw LiveTelemetryAcquisitionRecordingError.storageFailed
            }
        }
        self.session = session
    }

    /// 未完了batchを打ち切って残りをcommitし、区間を終了します。
    ///
    /// 責務: 取得終了時の最終commitと区間終了を行い、すべて保存できたかを返します。
    /// - Parameters:
    ///   - session: 終える世代の記録状態。
    ///   - reason: 取得が終わった直接原因。
    /// - Returns: 最終commit(または欠損記録)と区間終了がどちらも成功した場合は `true`。
    ///   途絶中で区間が既に閉じている場合は区間を終了しません。
    private func closeSession(_ session: AcquisitionRecordingSession, reason: ConnectionSessionEndReason) -> Bool {
        var succeeded = true
        if !hasStorageFailed {
            buffer.abandonOpenBatch(at: now(), classifier: classifier)
            do {
                try commitPending()
            } catch {
                succeeded = false
            }
        }
        guard session.isSegmentOpen else { return succeeded }
        do {
            try segmentSwitcher.close(
                session,
                endedAt: now(),
                reason: reason == .connectionLost ? .linkLost : .sessionEnded,
                lastCommittedSequence: buffer.lastCommittedSequence
            )
        } catch {
            succeeded = false
        }
        return succeeded
    }
}
