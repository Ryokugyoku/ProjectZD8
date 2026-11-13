import Foundation

/// 1回の取得batchを実行するために確定済みのApplication入力です。
nonisolated struct PersistAcquisitionBatchInput: Sendable {
    /// manifestとRaw開始境界の保存済み許可です。
    let permission: ConnectionSessionRawAcquisitionPermission
    /// session内のbatch identityです。
    let batchIdentity: AcquisitionBatchIdentity
    /// policyが評価した単調tickです。
    let policyTick: UInt
    /// batch開始を観測した実時間です。
    let startedAt: Date
    /// manifest要求順と一致する取得時PID定義です。
    let definitions: [OBDPIDDefinition]
    /// 物理取得に使用するOBD終端です。
    let endpoint: OBDConnectionEndpoint

    /// batch取得に必要な保存済み許可、定義、物理終端を固定します。
    ///
    /// 責務: 1回の取得batchへ必要な確定済み入力を推測なしでまとめます。
    /// - Parameters:
    ///   - permission: manifestとRaw開始境界の保存済み許可。
    ///   - batchIdentity: session内のbatch identity。
    ///   - policyTick: policyが評価した単調tick。
    ///   - startedAt: batch開始を観測した実時間。
    ///   - definitions: manifest要求順と一致する取得時PID定義。
    ///   - endpoint: 物理取得に使用するOBD終端。
    init(
        permission: ConnectionSessionRawAcquisitionPermission,
        batchIdentity: AcquisitionBatchIdentity,
        policyTick: UInt,
        startedAt: Date,
        definitions: [OBDPIDDefinition],
        endpoint: OBDConnectionEndpoint
    ) {
        self.permission = permission
        self.batchIdentity = batchIdentity
        self.policyTick = policyTick
        self.startedAt = startedAt
        self.definitions = definitions
        self.endpoint = endpoint
    }
}

/// batch取得を安全に完了できなかったApplication上の理由です。
nonisolated enum PersistAcquisitionBatchError: Error, Equatable, Sendable {
    /// 要求が現在のpolling世代に属していません。
    case inactiveGeneration
    /// manifest要求順と取得定義が一致しません。
    case invalidInput
    /// metadataまたはRawの永続化に失敗しました。
    case persistenceFailure
}

/// 方式Bで確定したbatch証拠と同じ物理応答から生成した表示用sampleです。
nonisolated struct PersistedAcquisitionBatchResult: Sendable {
    /// repositoryからcanonical readbackされたbatch証拠です。
    let evidence: AcquisitionBatchEvidence
    /// 今回新しく受信した正応答から生成した表示用sampleです。
    let samples: [OBDPIDSample]

    /// 永続証拠と表示用sampleを対応付けます。
    ///
    /// 責務: 1 batchの永続結果と再送不要の表示結果を同じ戻り値へまとめます。
    /// - Parameters:
    ///   - evidence: repositoryからcanonical readbackされたbatch証拠。
    ///   - samples: 今回新しく受信した正応答から生成した表示用sample。
    init(evidence: AcquisitionBatchEvidence, samples: [OBDPIDSample]) {
        self.evidence = evidence
        self.samples = samples
    }
}

/// PID単位のtyped Transport観測をRawとrequest evidenceへ順序付きで保存します。
actor PersistAcquisitionBatchUseCase {
    /// batch、request、Raw参照を保存するDomain repositoryです。
    private let repository: any ConnectionSessionAcquisitionBatchRepository
    /// PID単位のtyped Transport観測を返す取得境界です。
    private let telemetry: any OBDPIDTelemetryPort
    /// 取得時定義の制限付き数式を評価します。
    private let evaluator: OBDPIDFormulaEvaluator
    /// Raw観測日時とbatch完了日時を供給します。
    private let now: @Sendable () -> Date
    /// request単位の単調経過時間を供給します。
    private let monotonicNanoseconds: @Sendable () -> UInt64
    /// request transport区間を通知する匿名計測境界です。
    private let performanceEvents: any AcquisitionPerformanceEventPort
    /// 現在の取得workflowが有効としたpolling世代です。
    private var activeGeneration: UInt?

    /// repository、typed Transport、評価器、clockを固定します。
    ///
    /// 責務: 1 batch取得証拠workflowの副作用境界を注入します。
    /// - Parameters:
    ///   - repository: batch、request、Raw参照を保存するDomain repository。
    ///   - telemetry: PID単位のtyped Transport観測を返す取得境界。
    ///   - evaluator: 取得時PID定義の数式評価器。
    ///   - now: Raw観測日時とbatch完了日時の供給元。
    ///   - monotonicNanoseconds: request単位の単調clock。
    ///   - performanceEvents: request transport区間を通知する匿名計測境界。
    init(
        repository: any ConnectionSessionAcquisitionBatchRepository,
        telemetry: any OBDPIDTelemetryPort,
        evaluator: OBDPIDFormulaEvaluator = .init(),
        now: @escaping @Sendable () -> Date = Date.init,
        monotonicNanoseconds: @escaping @Sendable () -> UInt64,
        performanceEvents: any AcquisitionPerformanceEventPort = NoOpAcquisitionPerformanceEventPort()
    ) {
        self.repository = repository
        self.telemetry = telemetry
        self.evaluator = evaluator
        self.now = now
        self.monotonicNanoseconds = monotonicNanoseconds
        self.performanceEvents = performanceEvents
        activeGeneration = nil
    }

    /// 新しいpolling世代だけをbatch取得対象として有効化します。
    ///
    /// 責務: 後続のbatch結果を照合する現在世代を置き換えます。
    /// - Parameter generation: 有効化するpolling世代。
    func activate(generation: UInt) {
        activeGeneration = generation
    }

    /// 指定polling世代の後続永続化を無効化します。
    ///
    /// 責務: 現在世代と一致するbatch workflowだけをstale状態へ遷移させます。
    /// - Parameter generation: 無効化するpolling世代。
    func cancel(generation: UInt) {
        guard activeGeneration == generation else { return }
        activeGeneration = nil
    }

    /// 1 batchをdispatch開始、typed観測、request保存、batch確定の順で実行します。
    ///
    /// 責務: 現在世代のPID要求列をpartial失敗を保持する永続取得証拠へ変換します。
    /// - Parameter input: 保存済みmanifest許可と要求順定義を持つbatch入力。
    /// - Returns: repositoryからcanonical readbackされたterminal batch証拠。
    /// - Throws: stale世代、入力不一致、metadataまたはRaw保存失敗。
    func execute(_ input: PersistAcquisitionBatchInput) async throws -> AcquisitionBatchEvidence {
        try await executeWithSamples(input).evidence
    }

    /// 1 batchを方式Bで保存し、同じ正応答から表示用sampleも生成します。
    ///
    /// 責務: 現在世代のPID要求列を永続取得証拠と再送不要の表示用sampleへ変換します。
    /// - Parameter input: 保存済みmanifest許可と要求順定義を持つbatch入力。
    /// - Returns: canonical batch証拠と今回新しく受信した表示用sample。
    /// - Throws: stale世代、入力不一致、metadataまたはRaw保存失敗。
    func executeWithSamples(
        _ input: PersistAcquisitionBatchInput
    ) async throws -> PersistedAcquisitionBatchResult {
        do {
            try ensureCurrent(input.permission.generation)
            let requests = try validatedRequests(input)
            let open = try AcquisitionBatchEvidence(
                identity: input.batchIdentity,
                generation: input.permission.generation,
                policyTick: input.policyTick,
                isSelectionEvaluationComplete: true,
                startedAt: input.startedAt,
                completionState: nil,
                completedAt: nil,
                failure: nil,
                requests: try requests.enumerated().map { ordinal, item in
                    try PIDRequestEvidence(
                        requestOrdinal: ordinal,
                        manifestPIDOrdinal: item.manifestPIDOrdinal,
                        dispatchState: .selectedOnly,
                        transportOutcome: nil,
                        valueOutcome: .notEvaluated,
                        rawSequence: nil,
                        elapsedNanoseconds: nil,
                        reasonCode: nil
                    )
                }
            )
            let resumed = try beginOrResume(open, sessionID: input.permission.sessionID)
            if resumed.completionState != nil {
                return PersistedAcquisitionBatchResult(evidence: resumed, samples: [])
            }
            guard !resumed.requests.contains(where: { $0.dispatchState == .dispatchBegun }) else {
                throw PersistAcquisitionBatchError.persistenceFailure
            }
            var persistedRequests = resumed.requests
            var samples: [OBDPIDSample] = []
            for (ordinal, item) in requests.enumerated() {
                try ensureCurrent(input.permission.generation)
                if persistedRequests[ordinal].dispatchState == .terminal { continue }
                try repository.markRequestDispatchBegun(
                    requestOrdinal: ordinal,
                    in: input.batchIdentity,
                    for: input.permission.sessionID
                )
                let transportInterval = performanceEvents.begin(
                    .requestTransport,
                    context: AcquisitionPerformanceContext(
                        generation: input.permission.generation,
                        batchOrdinal: input.batchIdentity.ordinal,
                        requestOrdinal: ordinal,
                        policyTick: input.policyTick
                    )
                )
                let started = monotonicNanoseconds()
                let outcome = await transportOutcome(
                    for: item.definition,
                    endpoint: input.endpoint
                )
                let ended = monotonicNanoseconds()
                guard ended >= started else {
                    performanceEvents.end(transportInterval, outcome: .failed)
                    throw PersistAcquisitionBatchError.invalidInput
                }
                performanceEvents.end(
                    transportInterval,
                    outcome: outcome == .cancelled ? .cancelled : .succeeded
                )
                try ensureCurrent(input.permission.generation)
                let observedAt = now()
                persistedRequests[ordinal] = try persist(
                    outcome: outcome,
                    definition: item.definition,
                    observedAt: observedAt,
                    elapsedNanoseconds: ended - started,
                    requestOrdinal: ordinal,
                    batchIdentity: input.batchIdentity,
                    sessionID: input.permission.sessionID
                )
                if case let .responded(payload) = outcome,
                   let sample = decodedSample(
                    definition: item.definition,
                    payload: payload,
                    observedAt: observedAt
                   ) {
                    samples.append(sample)
                }
            }
            let terminal = try terminalBatch(from: resumed, requests: persistedRequests, completedAt: now())
            try repository.finishBatch(terminal, for: input.permission.sessionID)
            return PersistedAcquisitionBatchResult(evidence: terminal, samples: samples)
        } catch let error as PersistAcquisitionBatchError {
            throw error
        } catch is CancellationError {
            throw PersistAcquisitionBatchError.inactiveGeneration
        } catch {
            throw PersistAcquisitionBatchError.persistenceFailure
        }
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

    /// manifest要求順と取得定義を照合します。
    ///
    /// 責務: 保存済みordered PID集合を同順序の完全な取得定義列へ結び付けます。
    /// - Parameter input: manifest許可と取得定義を持つbatch入力。
    /// - Returns: manifest位置を付与した取得定義列。
    /// - Throws: 欠落、順序不一致、または片側だけのrange指定では `.invalidInput`。
    private func validatedRequests(
        _ input: PersistAcquisitionBatchInput
    ) throws -> [(manifestPIDOrdinal: Int, definition: OBDPIDDefinition)] {
        guard let ordered = input.permission.manifest.orderedRequestedPIDs else {
            throw PersistAcquisitionBatchError.invalidInput
        }
        let manifestOrdinalByRequest = Dictionary(
            uniqueKeysWithValues: ordered.requests.enumerated().map { ($0.element, $0.offset) }
        )
        let requested = input.definitions.map {
            OBDPIDRequest(service: $0.service, pid: $0.pid)
        }
        guard Set(requested).count == requested.count else {
            throw PersistAcquisitionBatchError.invalidInput
        }
        return try input.definitions.map { definition in
            let request = OBDPIDRequest(service: definition.service, pid: definition.pid)
            guard let manifestOrdinal = manifestOrdinalByRequest[request],
                  (definition.minimumValue == nil) == (definition.maximumValue == nil) else {
                throw PersistAcquisitionBatchError.invalidInput
            }
            return (manifestOrdinal, definition)
        }
    }

    /// open batchを新規作成し、exact retryでは保存済みcanonical状態を返します。
    ///
    /// 責務: 1件のbatch開始を新規保存または同一入力の再開状態へ決定します。
    /// - Parameters:
    ///   - open: 今回期待するopen batch証拠。
    ///   - sessionID: batchを所有するsession。
    /// - Returns: 新規またはexact retryとして読み戻したcanonical batch。
    /// - Throws: semantic差、読取失敗、または保存失敗。
    private func beginOrResume(
        _ open: AcquisitionBatchEvidence,
        sessionID: ConnectionSessionID
    ) throws -> AcquisitionBatchEvidence {
        if let stored = try repository.batches(for: sessionID).first(where: {
            $0.identity == open.identity
        }) {
            guard stored.identity == open.identity,
                  stored.generation == open.generation,
                  stored.policyTick == open.policyTick,
                  stored.startedAt == open.startedAt,
                  stored.requests.map(\.manifestPIDOrdinal) == open.requests.map(\.manifestPIDOrdinal) else {
                throw PersistAcquisitionBatchError.persistenceFailure
            }
            return stored
        }
        try repository.beginBatch(open, for: sessionID)
        return open
    }

    /// 1件のPIDをtyped Transport観測へ変換します。
    ///
    /// 責務: 1要求だけを実行し、throwや観測不一致をunsupportedへ推測しない排他結果へ変換します。
    /// - Parameters:
    ///   - definition: 実行する取得時PID定義。
    ///   - endpoint: 使用するOBD終端。
    /// - Returns: 明示typed結果、または安全なcancel、transport failure、unclassified結果。
    private func transportOutcome(
        for definition: OBDPIDDefinition,
        endpoint: OBDConnectionEndpoint
    ) async -> OBDPIDRequestTransportOutcome {
        let request = OBDPIDRequest(service: definition.service, pid: definition.pid)
        do {
            if definition.isVehicleSpecific {
                let responses = try await telemetry.readVehicleSpecific([definition], using: endpoint)
                guard let payload = responses[request] else { return .unclassifiedResponse }
                return .responded(payload)
            }
            let observations = try await telemetry.readObservations([request], using: endpoint)
            guard observations.count == 1, observations[0].request == request else {
                return .unclassifiedResponse
            }
            return observations[0].outcome
        } catch is CancellationError {
            return .cancelled
        } catch let error as OBDPIDTelemetryError {
            switch error {
            case .connectionLost, .unavailable:
                return .transportFailure
            case .definitionCatalogUnavailable, .unsupportedPID, .commandRejected,
                 .malformedResponse, .incompleteResponse, .noVehicleResponse:
                return .unclassifiedResponse
            }
        } catch {
            return .unclassifiedResponse
        }
    }

    /// typed Transport結果を対応するrepository terminal操作へ渡します。
    ///
    /// 責務: 1件のtyped観測を推測なしのDomain request evidenceへ永続化します。
    /// - Parameters:
    ///   - outcome: Transport境界が返した排他結果。
    ///   - definition: payload評価に使用する取得時定義。
    ///   - observedAt: Raw正応答を観測した実時間。
    ///   - elapsedNanoseconds: request開始からterminalまでの単調経過時間。
    ///   - requestOrdinal: batch内要求順。
    ///   - batchIdentity: 親batch identity。
    ///   - sessionID: 親session。
    /// - Returns: repositoryから返されたcanonical request evidence。
    /// - Throws: Domain evidence生成または永続化失敗。
    private func persist(
        outcome: OBDPIDRequestTransportOutcome,
        definition: OBDPIDDefinition,
        observedAt: Date,
        elapsedNanoseconds: UInt64,
        requestOrdinal: Int,
        batchIdentity: AcquisitionBatchIdentity,
        sessionID: ConnectionSessionID
    ) throws -> PIDRequestEvidence {
        switch outcome {
        case let .responded(payload):
            let valueOutcome = evaluateValueOutcome(definition: definition, payload: payload)
            return try repository.saveRespondedRequest(
                observation: OBDRawResponseObservation(
                    observedAt: observedAt,
                    batchElapsedNanoseconds: elapsedNanoseconds,
                    request: OBDPIDRequest(service: definition.service, pid: definition.pid),
                    payload: payload
                ),
                valueOutcome: valueOutcome,
                elapsedNanoseconds: elapsedNanoseconds,
                reasonCode: nil,
                requestOrdinal: requestOrdinal,
                in: batchIdentity,
                for: sessionID
            )
        case .unsupported:
            return try saveNonResponded(.unsupported, reasonCode: "explicit_unsupported", elapsedNanoseconds: elapsedNanoseconds, requestOrdinal: requestOrdinal, batchIdentity: batchIdentity, sessionID: sessionID)
        case .timedOut:
            return try saveNonResponded(.timedOut, reasonCode: "response_timeout", elapsedNanoseconds: elapsedNanoseconds, requestOrdinal: requestOrdinal, batchIdentity: batchIdentity, sessionID: sessionID)
        case .cancelled:
            return try saveNonResponded(.cancelled, reasonCode: "explicit_cancellation", elapsedNanoseconds: elapsedNanoseconds, requestOrdinal: requestOrdinal, batchIdentity: batchIdentity, sessionID: sessionID)
        case .transportFailure:
            return try saveNonResponded(.transportFailure, reasonCode: "transport_boundary_lost", elapsedNanoseconds: elapsedNanoseconds, requestOrdinal: requestOrdinal, batchIdentity: batchIdentity, sessionID: sessionID)
        case .unclassifiedResponse:
            return try saveNonResponded(.unclassifiedResponse, reasonCode: "unclassified_transport_result", elapsedNanoseconds: elapsedNanoseconds, requestOrdinal: requestOrdinal, batchIdentity: batchIdentity, sessionID: sessionID)
        }
    }

    /// nonresponded結果をrepositoryへ渡します。
    ///
    /// 責務: 1件の非responded typed結果をRawなしのterminal保存へ変換します。
    /// - Parameters:
    ///   - outcome: 保存する非responded Domain結果。
    ///   - reasonCode: 承認済み分類理由code。
    ///   - elapsedNanoseconds: request開始からterminalまでの単調経過時間。
    ///   - requestOrdinal: batch内要求順。
    ///   - batchIdentity: 親batch identity。
    ///   - sessionID: 親session。
    /// - Returns: canonical request evidence。
    /// - Throws: repository保存失敗。
    private func saveNonResponded(
        _ outcome: PIDRequestTransportOutcome,
        reasonCode: String,
        elapsedNanoseconds: UInt64,
        requestOrdinal: Int,
        batchIdentity: AcquisitionBatchIdentity,
        sessionID: ConnectionSessionID
    ) throws -> PIDRequestEvidence {
        try repository.saveNonRespondedRequest(
            outcome: outcome,
            elapsedNanoseconds: elapsedNanoseconds,
            reasonCode: reasonCode,
            requestOrdinal: requestOrdinal,
            in: batchIdentity,
            for: sessionID
        )
    }

    /// responded payloadの取得時値評価結果を分類します。
    ///
    /// 責務: 取得時PID定義とpayloadをdecode、finite、明示rangeの排他結果へ変換します。
    /// - Parameters:
    ///   - definition: 取得時の数式と任意の両端rangeを持つ定義。
    ///   - payload: 未デコード正応答bytes。
    /// - Returns: decode成功、decode失敗、または無効値の分類。
    private func evaluateValueOutcome(
        definition: OBDPIDDefinition,
        payload: [UInt8]
    ) -> PIDRequestValueOutcome {
        do {
            let value = try evaluator.evaluate(definition, bytes: payload)
            guard value.isFinite else { return .invalidValue }
            if let minimum = definition.minimumValue, let maximum = definition.maximumValue,
               !(minimum...maximum).contains(value) {
                return .invalidValue
            }
            return .decodedValid
        } catch OBDPIDFormulaError.nonFiniteResult {
            return .invalidValue
        } catch {
            return .decodeFailure
        }
    }

    /// 正応答payloadをLiveTelemetry表示用sampleへ変換します。
    ///
    /// 責務: 1件の取得時定義と正応答を再送なしの数値観測へ変換します。
    /// - Parameters:
    ///   - definition: 表示metadataと数式を持つ取得時PID定義。
    ///   - payload: 方式BでRaw保存した正応答bytes。
    ///   - observedAt: Rawと共有する観測日時。
    /// - Returns: 数値化できた表示用sample、またはdecode不能時の `nil`。
    private func decodedSample(
        definition: OBDPIDDefinition,
        payload: [UInt8],
        observedAt: Date
    ) -> OBDPIDSample? {
        guard let value = try? evaluator.evaluate(definition, bytes: payload), value.isFinite else {
            return nil
        }
        return OBDPIDSample(
            request: OBDPIDRequest(service: definition.service, pid: definition.pid),
            nameKey: definition.nameKey,
            value: value,
            unit: definition.unit,
            vehicleModelCode: definition.vehicleModelCode,
            observedAt: observedAt,
            summaryKey: definition.summaryKey,
            highValueKey: definition.highValueKey,
            lowValueKey: definition.lowValueKey,
            correlationKey: definition.correlationKey
        )
    }

    /// request結果列からbatch terminal状態を決定します。
    ///
    /// 責務: 排他的request outcome列をcompletedまたは明示partial failureへ集約します。
    /// - Parameters:
    ///   - open: 保存済みopen batch証拠。
    ///   - requests: canonical terminal request列。
    ///   - completedAt: batch terminal確定日時。
    /// - Returns: 完了またはpartial失敗を持つterminal batch証拠。
    /// - Throws: Domain batch不変条件違反。
    private func terminalBatch(
        from open: AcquisitionBatchEvidence,
        requests: [PIDRequestEvidence],
        completedAt: Date
    ) throws -> AcquisitionBatchEvidence {
        let outcomes = requests.compactMap(\.transportOutcome)
        let failure: AcquisitionBatchFailure?
        if outcomes.contains(.cancelled) {
            failure = .cancelled
        } else if outcomes.contains(.transportFailure) || outcomes.contains(.timedOut) {
            failure = .transportUnavailable
        } else if outcomes.contains(.unclassifiedResponse) {
            failure = .unclassifiedResult
        } else {
            failure = nil
        }
        return try AcquisitionBatchEvidence(
            identity: open.identity,
            generation: open.generation,
            policyTick: open.policyTick,
            isSelectionEvaluationComplete: open.isSelectionEvaluationComplete,
            startedAt: open.startedAt,
            completionState: failure == nil ? .completed : .failed,
            completedAt: completedAt,
            failure: failure,
            requests: requests
        )
    }

    /// 指定世代が現在の取得workflowに属することを検証します。
    ///
    /// 責務: staleまたはcancel済み世代を次の永続化処理より前に拒否します。
    /// - Parameter generation: 検証するpolling世代。
    /// - Throws: 現在世代と一致しない場合は `.inactiveGeneration`。
    private func ensureCurrent(_ generation: UInt) throws {
        guard activeGeneration == generation else {
            throw PersistAcquisitionBatchError.inactiveGeneration
        }
    }
}
