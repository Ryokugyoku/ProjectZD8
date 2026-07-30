import Foundation
import XCTest
@testable import ProjectZD8

/// PID単位typed観測からbatch取得証拠を保存するApplication orchestrationを検証します。
@MainActor
final class PersistAcquisitionBatchUseCaseTests: XCTestCase {
    /// decode成功をresponded Raw参照とdecoded-validへ保存します。
    ///
    /// 責務: 正応答payloadが有限range内の値と採番済みRaw sequenceへ変換されることを確認します。
    func testRespondedDecodeSuccessPersistsRawSequenceAndValidOutcome() async throws {
        let fixture = try await makeFixture(outcomes: [.responded([50])])

        let result = try await fixture.useCase.execute(fixture.input)

        XCTAssertEqual(result.completionState, .completed)
        XCTAssertEqual(result.requests[0].valueOutcome, .decodedValid)
        XCTAssertEqual(result.requests[0].rawSequence, 0)
        XCTAssertEqual(fixture.repository.respondedObservations.map(\.payload), [[50]])
    }

    /// 数式評価失敗をRawを保持したdecode failureへ保存します。
    ///
    /// 責務: bytes不足が正応答消失やtransport failureへ変換されないことを確認します。
    func testRespondedDecodeFailureKeepsRaw() async throws {
        let definition = makeDefinition(requiredByteCount: 2, formula: "A + B")
        let fixture = try await makeFixture(definitions: [definition], outcomes: [.responded([1])])

        let result = try await fixture.useCase.execute(fixture.input)

        XCTAssertEqual(result.requests[0].valueOutcome, .decodeFailure)
        XCTAssertEqual(result.requests[0].rawSequence, 0)
        XCTAssertEqual(fixture.repository.respondedObservations.count, 1)
    }

    /// range外の有限値をinvalid valueへ保存します。
    ///
    /// 責務: 明示range外のdecode成功値をdecoded-validと混同しないことを確認します。
    func testRespondedOutOfRangePersistsInvalidValue() async throws {
        let fixture = try await makeFixture(outcomes: [.responded([101])])

        let result = try await fixture.useCase.execute(fixture.input)

        XCTAssertEqual(result.requests[0].valueOutcome, .invalidValue)
        XCTAssertEqual(result.requests[0].rawSequence, 0)
    }

    /// timeoutはRawを作らずpartial batchを確定します。
    ///
    /// 責務: typed timeoutを非responded evidenceとbatch transport failureへ変換します。
    func testTimeoutCreatesNoRawAndFinishesPartialBatch() async throws {
        let fixture = try await makeFixture(outcomes: [.timedOut])

        let result = try await fixture.useCase.execute(fixture.input)

        XCTAssertTrue(fixture.repository.respondedObservations.isEmpty)
        XCTAssertEqual(result.requests[0].transportOutcome, .timedOut)
        XCTAssertNil(result.requests[0].rawSequence)
        XCTAssertEqual(result.completionState, .failed)
        XCTAssertEqual(result.failure, .transportUnavailable)
    }

    /// explicit unsupportedだけをunsupportedへ保存します。
    ///
    /// 責務: adapter typed証拠を持つunsupportedが通常throwやunclassifiedと別経路になることを確認します。
    func testExplicitUnsupportedIsPersistedWithoutRaw() async throws {
        let fixture = try await makeFixture(outcomes: [.unsupported])

        let result = try await fixture.useCase.execute(fixture.input)

        XCTAssertEqual(result.requests[0].transportOutcome, .unsupported)
        XCTAssertEqual(result.completionState, .completed)
        XCTAssertTrue(fixture.repository.respondedObservations.isEmpty)
    }

    /// explicit cancelをunknown-after-terminationと異なるpartial結果へ保存します。
    ///
    /// 責務: typed取消しをcancelled requestとcancelled batch failureへ変換します。
    func testExplicitCancellationRemainsDistinctFromTerminationRecovery() async throws {
        let fixture = try await makeFixture(outcomes: [.cancelled])

        let result = try await fixture.useCase.execute(fixture.input)

        XCTAssertEqual(result.requests[0].transportOutcome, .cancelled)
        XCTAssertNotEqual(result.requests[0].transportOutcome, .unknownAfterTermination)
        XCTAssertEqual(result.failure, .cancelled)
        XCTAssertTrue(fixture.repository.respondedObservations.isEmpty)
    }

    /// stale世代を最初のmetadata永続化前に拒否します。
    ///
    /// 責務: 現在世代と異なるbatchがopen evidenceを作らないことを確認します。
    func testStaleGenerationIsRejectedBeforePersistence() async throws {
        let fixture = try await makeFixture(outcomes: [.responded([1])], activateGeneration: 2)

        await XCTAssertThrowsErrorAsync(try await fixture.useCase.execute(fixture.input)) {
            XCTAssertEqual($0 as? PersistAcquisitionBatchError, .inactiveGeneration)
        }
        XCTAssertTrue(fixture.repository.events.isEmpty)
    }

    /// metadata保存失敗を成功結果へ変換しません。
    ///
    /// 責務: open batch永続化失敗がtransport実行や空batch成功へ進まないことを確認します。
    func testMetadataPersistenceFailureIsNotReportedAsSuccess() async throws {
        let fixture = try await makeFixture(outcomes: [.responded([1])])
        fixture.repository.failurePoint = .beginBatch

        await XCTAssertThrowsErrorAsync(try await fixture.useCase.execute(fixture.input)) {
            XCTAssertEqual($0 as? PersistAcquisitionBatchError, .persistenceFailure)
        }
        XCTAssertEqual(fixture.repository.events, [.beginBatch])
        let readCount = await fixture.telemetry.readCount
        XCTAssertEqual(readCount, 0)
    }

    /// responded Raw保存失敗を成功や空応答へ変換しません。
    ///
    /// 責務: typed正応答後の原子repository失敗を明示persistence failureとして返します。
    func testRawPersistenceFailureIsNotReportedAsSuccess() async throws {
        let definitions = [makeDefinition(pid: 12), makeDefinition(pid: 13)]
        let fixture = try await makeFixture(definitions: definitions, outcomes: [.responded([50]), .responded([60])])
        fixture.repository.failurePoint = .responded

        await XCTAssertThrowsErrorAsync(try await fixture.useCase.execute(fixture.input)) {
            XCTAssertEqual($0 as? PersistAcquisitionBatchError, .persistenceFailure)
        }
        XCTAssertEqual(fixture.repository.events, [.beginBatch, .dispatch(0), .responded(0)])
        XCTAssertTrue(fixture.repository.respondedObservations.isEmpty)
        let readCount = await fixture.telemetry.readCount
        XCTAssertEqual(readCount, 1)
    }

    /// polling subsetのrequestへmanifest内の元ordinalを保持します。
    ///
    /// 責務: 間引かれた取得定義をbatch内順とmanifest内順の異なる決定的identityへ対応付けます。
    func testPollingSubsetRetainsManifestOrdinal() async throws {
        let manifestDefinitions = [makeDefinition(pid: 12), makeDefinition(pid: 13)]
        let fixture = try await makeFixture(
            definitions: [manifestDefinitions[1]],
            manifestDefinitions: manifestDefinitions,
            outcomes: [.responded([50])]
        )

        let result = try await fixture.useCase.execute(fixture.input)

        XCTAssertEqual(result.requests.map(\.requestOrdinal), [0])
        XCTAssertEqual(result.requests.map(\.manifestPIDOrdinal), [1])
        XCTAssertEqual(result.requests.map(\.transportOutcome), [.responded])
    }

    /// 成功要求とtimeoutを同じpartial batchへ保持します。
    ///
    /// 責務: 途中terminal failureが先行responded Rawを消さずbatch失敗として確定されることを確認します。
    func testMixedRespondedAndTimeoutFinishesPartialBatch() async throws {
        let definitions = [makeDefinition(pid: 12), makeDefinition(pid: 13)]
        let fixture = try await makeFixture(definitions: definitions, outcomes: [.responded([50]), .timedOut])

        let result = try await fixture.useCase.execute(fixture.input)

        XCTAssertEqual(result.requests.map(\.transportOutcome), [.responded, .timedOut])
        XCTAssertEqual(result.completionState, .failed)
        XCTAssertEqual(result.failure, .transportUnavailable)
        XCTAssertEqual(fixture.repository.respondedObservations.count, 1)
    }

    /// process終了回復はdispatch済み要求だけをunknownへ遷移させます。
    ///
    /// 責務: 明示cancelと異なるunknown-after-terminationをselected-only要求と共存させます。
    func testTerminationRecoveryKeepsUnknownDistinctFromCancellation() async throws {
        let definitions = [makeDefinition(pid: 12), makeDefinition(pid: 13)]
        let fixture = try await makeFixture(definitions: definitions, outcomes: [])
        try fixture.repository.beginBatch(try openBatch(for: fixture.input), for: fixture.input.permission.sessionID)
        try fixture.repository.markRequestDispatchBegun(
            requestOrdinal: 0,
            in: fixture.input.batchIdentity,
            for: fixture.input.permission.sessionID
        )

        let result = try await fixture.useCase.recoverAfterTermination(
            batchIdentity: fixture.input.batchIdentity,
            for: fixture.input.permission.sessionID,
            completedAt: Date(timeIntervalSince1970: 30)
        )

        XCTAssertEqual(result.requests[0].transportOutcome, .unknownAfterTermination)
        XCTAssertNil(result.requests[0].elapsedNanoseconds)
        XCTAssertEqual(result.requests[1].dispatchState, .selectedOnly)
        XCTAssertNotEqual(result.requests[0].transportOutcome, .cancelled)
        XCTAssertEqual(result.completionState, .terminatedUnknown)
    }

    /// Application test依存と入力を生成します。
    ///
    /// 責務: fake repository、typed telemetry、clock、manifest許可を同じbatch fixtureへまとめます。
    /// - Parameters:
    ///   - definitions: manifest順の取得時PID定義。
    ///   - manifestDefinitions: manifestへ固定する全取得時PID定義。省略時は `definitions` と同一。
    ///   - outcomes: request順に返すtyped Transport結果。
    ///   - activateGeneration: use caseへ有効化する世代。
    /// - Returns: 実行可能なApplication fixture。
    private func makeFixture(
        definitions requestedDefinitions: [OBDPIDDefinition]? = nil,
        manifestDefinitions requestedManifestDefinitions: [OBDPIDDefinition]? = nil,
        outcomes: [OBDPIDRequestTransportOutcome],
        activateGeneration: UInt = 1
    ) async throws -> AcquisitionUseCaseFixture {
        let definitions = requestedDefinitions ?? [makeDefinition()]
        let manifestDefinitions = requestedManifestDefinitions ?? definitions
        let repository = AcquisitionBatchRepositoryFake()
        let telemetry = AcquisitionTelemetryFake(outcomes: outcomes)
        let clock = MonotonicSequence(values: Array(0..<(max(1, definitions.count) * 2)).map { UInt64($0 * 100) })
        let useCase = PersistAcquisitionBatchUseCase(
            repository: repository,
            telemetry: telemetry,
            now: { Date(timeIntervalSince1970: 20) },
            monotonicNanoseconds: { clock.next() }
        )
        let manifest = try makeManifest(definitions: manifestDefinitions)
        let permission = ConnectionSessionRawAcquisitionPermission(
            sessionID: ConnectionSessionID(rawValue: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!),
            generation: 1,
            manifest: manifest
        )
        let input = PersistAcquisitionBatchInput(
            permission: permission,
            batchIdentity: try AcquisitionBatchIdentity(ordinal: 0),
            policyTick: 0,
            startedAt: Date(timeIntervalSince1970: 10),
            definitions: definitions,
            endpoint: OBDConnectionEndpoint(transport: .serial, systemIdentifier: "test", displayName: "test")
        )
        await useCase.activate(generation: activateGeneration)
        return AcquisitionUseCaseFixture(repository: repository, telemetry: telemetry, useCase: useCase, input: input)
    }

    /// test用PID定義を生成します。
    ///
    /// 責務: decode、range、PIDだけを差し替え可能な取得定義を返します。
    /// - Parameters:
    ///   - pid: Service 1内のPID番号。
    ///   - requiredByteCount: 数式に必要なbytes数。
    ///   - formula: 評価する制限付き式。
    /// - Returns: 0...100の明示rangeを持つ定義。
    private func makeDefinition(
        pid: UInt8 = 12,
        requiredByteCount: Int = 1,
        formula: String = "A"
    ) -> OBDPIDDefinition {
        OBDPIDDefinition(
            service: 1,
            pid: pid,
            nameKey: "test.pid",
            requiredByteCount: requiredByteCount,
            formula: formula,
            unit: "unit",
            minimumValue: 0,
            maximumValue: 100,
            sourceURI: "test://pid",
            revision: 1
        )
    }

    /// test用完全manifestを生成します。
    ///
    /// 責務: 入力定義順をordered PID集合と完全snapshotへ固定します。
    /// - Parameter definitions: manifestへ含める取得定義。
    /// - Returns: Application batch入力に使用できる完全manifest。
    private func makeManifest(definitions: [OBDPIDDefinition]) throws -> ConnectionSessionAcquisitionManifest {
        let requests = definitions.map { OBDPIDRequest(service: $0.service, pid: $0.pid) }
        let snapshots = try definitions.map { definition in
            try AcquisitionPIDDefinitionSnapshot(
                request: OBDPIDRequest(service: definition.service, pid: definition.pid),
                capabilitySupport: .supported,
                isCollectionEnabled: true,
                definitionRevision: definition.revision,
                requiredByteCount: definition.requiredByteCount,
                definitionIdentity: AcquisitionPIDDefinitionIdentity(
                    canonicalizationVersion: 1,
                    expression: try XCTUnwrap(definition.formula)
                ),
                unit: definition.unit,
                validityRange: try .inclusive(
                    minimum: XCTUnwrap(definition.minimumValue),
                    maximum: XCTUnwrap(definition.maximumValue)
                )
            )
        }
        return try ConnectionSessionAcquisitionManifest(
            manifestVersion: 1,
            applicationVersion: AcquisitionApplicationVersion(marketingVersion: "1", buildVersion: "1"),
            schemaContractVersion: 1,
            pollingPolicyVersion: 1,
            orderedRequestedPIDs: OrderedAcquisitionPIDSet(requests: requests),
            pidDefinitions: snapshots,
            acquisitionPlatform: .macOS,
            modelInputManifestVersion: 1
        )
    }

    /// inputと同じselected-only open batchを生成します。
    ///
    /// 責務: termination recovery testへProduction use caseと同形のopen evidenceを渡します。
    /// - Parameter input: manifest順定義を持つbatch入力。
    /// - Returns: policy評価完了済みopen batch。
    private func openBatch(for input: PersistAcquisitionBatchInput) throws -> AcquisitionBatchEvidence {
        try AcquisitionBatchEvidence(
            identity: input.batchIdentity,
            generation: input.permission.generation,
            policyTick: input.policyTick,
            isSelectionEvaluationComplete: true,
            startedAt: input.startedAt,
            completionState: nil,
            completedAt: nil,
            failure: nil,
            requests: try input.definitions.enumerated().map { ordinal, _ in
                try PIDRequestEvidence(
                    requestOrdinal: ordinal,
                    manifestPIDOrdinal: ordinal,
                    dispatchState: .selectedOnly,
                    transportOutcome: nil,
                    valueOutcome: .notEvaluated,
                    rawSequence: nil,
                    elapsedNanoseconds: nil,
                    reasonCode: nil
                )
            }
        )
    }
}

/// async式が指定errorを送出することを検証します。
///
/// 責務: XCTestの同期assertionへasync throwing処理のerrorを橋渡しします。
/// - Parameters:
///   - expression: 評価するasync throwing式。
///   - errorHandler: 捕捉したerrorの検証処理。
private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error")
    } catch {
        errorHandler(error)
    }
}

/// Application batch testが共有する依存と入力です。
private struct AcquisitionUseCaseFixture {
    /// 記録内容を検査するfake repositoryです。
    let repository: AcquisitionBatchRepositoryFake
    /// typed Transport呼出しを検査するfakeです。
    let telemetry: AcquisitionTelemetryFake
    /// 検証対象のApplication use caseです。
    let useCase: PersistAcquisitionBatchUseCase
    /// 1 batch分の確定済み入力です。
    let input: PersistAcquisitionBatchInput
}

/// fake repositoryが失敗を注入できる永続化段階です。
private enum AcquisitionRepositoryFailurePoint {
    /// open batch保存段階です。
    case beginBatch
    /// responded Raw原子保存段階です。
    case responded
}

/// Application orchestration順とcanonical evidenceを記録するfake repositoryです。
private final class AcquisitionBatchRepositoryFake: ConnectionSessionAcquisitionBatchRepository, @unchecked Sendable {
    /// 呼出し順を記録するeventです。
    enum Event: Equatable {
        /// open batch保存です。
        case beginBatch
        /// request dispatch開始です。
        case dispatch(Int)
        /// responded原子保存です。
        case responded(Int)
        /// nonresponded terminal保存です。
        case nonResponded(Int)
        /// batch terminal確定です。
        case finishBatch
    }

    /// 注入する任意の失敗段階です。
    var failurePoint: AcquisitionRepositoryFailurePoint?
    /// 永続化呼出し順です。
    private(set) var events: [Event] = []
    /// responded保存へ渡されたRaw observationです。
    private(set) var respondedObservations: [OBDRawResponseObservation] = []
    /// 現在のbatch evidence列です。
    private var storedBatches: [AcquisitionBatchEvidence] = []

    /// open batchをfake永続状態へ保存します。
    ///
    /// 責務: begin呼出しを記録して任意のmetadata失敗を注入します。
    /// - Parameters:
    ///   - evidence: 保存するopen batch。
    ///   - sessionID: 使用しない親session。
    /// - Throws: 注入時はrepository unavailable。
    func beginBatch(_ evidence: AcquisitionBatchEvidence, for sessionID: ConnectionSessionID) throws {
        events.append(.beginBatch)
        if failurePoint == .beginBatch { throw ConnectionSessionAcquisitionRepositoryError.unavailable }
        storedBatches = [evidence]
    }

    /// requestをdispatch開始へ遷移させます。
    ///
    /// 責務: fake batch内の指定requestをdispatch開始済みとして記録します。
    /// - Parameters:
    ///   - requestOrdinal: batch内要求順。
    ///   - batchIdentity: 使用しない親batch identity。
    ///   - sessionID: 使用しない親session。
    /// - Throws: evidence再生成に失敗した場合のDomain error。
    func markRequestDispatchBegun(requestOrdinal: Int, in batchIdentity: AcquisitionBatchIdentity, for sessionID: ConnectionSessionID) throws {
        events.append(.dispatch(requestOrdinal))
        try replaceRequest(requestOrdinal) { stored in
            try PIDRequestEvidence(
                requestOrdinal: stored.requestOrdinal,
                manifestPIDOrdinal: stored.manifestPIDOrdinal,
                dispatchState: .dispatchBegun,
                transportOutcome: nil,
                valueOutcome: .notEvaluated,
                rawSequence: nil,
                elapsedNanoseconds: nil,
                reasonCode: nil
            )
        }
    }

    /// responded Rawとrequest terminalをfake保存します。
    ///
    /// 責務: Raw入力を記録して連続sequence付きcanonical requestを返します。
    /// - Returns: fake採番済みrequest evidence。
    func saveRespondedRequest(observation: OBDRawResponseObservation, valueOutcome: PIDRequestValueOutcome, elapsedNanoseconds: UInt64, reasonCode: String?, requestOrdinal: Int, in batchIdentity: AcquisitionBatchIdentity, for sessionID: ConnectionSessionID) throws -> PIDRequestEvidence {
        events.append(.responded(requestOrdinal))
        if failurePoint == .responded { throw ConnectionSessionAcquisitionRepositoryError.unavailable }
        let sequence = Int64(respondedObservations.count)
        respondedObservations.append(observation)
        var result: PIDRequestEvidence?
        try replaceRequest(requestOrdinal) { stored in
            let terminal = try PIDRequestEvidence(
                requestOrdinal: stored.requestOrdinal,
                manifestPIDOrdinal: stored.manifestPIDOrdinal,
                dispatchState: .terminal,
                transportOutcome: .responded,
                valueOutcome: valueOutcome,
                rawSequence: sequence,
                elapsedNanoseconds: elapsedNanoseconds,
                reasonCode: reasonCode
            )
            result = terminal
            return terminal
        }
        guard let result else { throw ConnectionSessionAcquisitionRepositoryError.unavailable }
        return result
    }

    /// nonresponded request terminalをfake保存します。
    ///
    /// 責務: Rawを生成せず指定outcomeのcanonical requestを返します。
    /// - Returns: fake terminal request evidence。
    func saveNonRespondedRequest(outcome: PIDRequestTransportOutcome, elapsedNanoseconds: UInt64?, reasonCode: String?, requestOrdinal: Int, in batchIdentity: AcquisitionBatchIdentity, for sessionID: ConnectionSessionID) throws -> PIDRequestEvidence {
        events.append(.nonResponded(requestOrdinal))
        var result: PIDRequestEvidence?
        try replaceRequest(requestOrdinal) { stored in
            let terminal = try PIDRequestEvidence(
                requestOrdinal: stored.requestOrdinal,
                manifestPIDOrdinal: stored.manifestPIDOrdinal,
                dispatchState: .terminal,
                transportOutcome: outcome,
                valueOutcome: .notEvaluated,
                rawSequence: nil,
                elapsedNanoseconds: elapsedNanoseconds,
                reasonCode: reasonCode
            )
            result = terminal
            return terminal
        }
        guard let result else { throw ConnectionSessionAcquisitionRepositoryError.unavailable }
        return result
    }

    /// terminal batchをfake保存します。
    ///
    /// 責務: Applicationが確定したpartialを含むterminal aggregateを記録します。
    /// - Parameters:
    ///   - evidence: 保存するterminal batch。
    ///   - sessionID: 使用しない親session。
    func finishBatch(_ evidence: AcquisitionBatchEvidence, for sessionID: ConnectionSessionID) throws {
        events.append(.finishBatch)
        storedBatches = [evidence]
    }

    /// 現在のfake batch列を返します。
    ///
    /// 責務: termination回復へ保存済みopen batchを提供します。
    /// - Parameter sessionID: 使用しない親session。
    /// - Returns: fake保存中のbatch列。
    func batches(for sessionID: ConnectionSessionID) throws -> [AcquisitionBatchEvidence] { storedBatches }

    /// 指定requestだけを置換してopen batchを再生成します。
    ///
    /// 責務: fakeのrequest遷移をDomain aggregate不変条件へ反映します。
    /// - Parameters:
    ///   - ordinal: 置換するrequest順。
    ///   - transform: 現在requestを次状態へ変換する処理。
    /// - Throws: batch不在またはDomain不変条件違反。
    private func replaceRequest(
        _ ordinal: Int,
        transform: (PIDRequestEvidence) throws -> PIDRequestEvidence
    ) throws {
        guard let batch = storedBatches.first else { throw ConnectionSessionAcquisitionRepositoryError.notFound }
        var requests = batch.requests
        requests[ordinal] = try transform(requests[ordinal])
        storedBatches = [try AcquisitionBatchEvidence(
            identity: batch.identity,
            generation: batch.generation,
            policyTick: batch.policyTick,
            isSelectionEvaluationComplete: batch.isSelectionEvaluationComplete,
            startedAt: batch.startedAt,
            completionState: nil,
            completedAt: nil,
            failure: nil,
            requests: requests
        )]
    }
}

/// request順にtyped Transport結果を返すfake telemetryです。
private actor AcquisitionTelemetryFake: OBDPIDTelemetryPort {
    /// 未返却のtyped outcome列です。
    private var outcomes: [OBDPIDRequestTransportOutcome]
    /// PID単位読取回数です。
    private(set) var readCount = 0

    /// 返却するtyped outcome列を固定します。
    ///
    /// 責務: Application testのTransport結果順を初期化します。
    /// - Parameter outcomes: request順に返すtyped結果。
    init(outcomes: [OBDPIDRequestTransportOutcome]) { self.outcomes = outcomes }

    /// 1要求へ次のtyped outcomeを返します。
    ///
    /// 責務: 要求と次のfake outcomeを1件のtyped観測へ対応付けます。
    /// - Returns: 入力要求に対応する0件または1件の観測。
    func readObservations(_ requests: [OBDPIDRequest], using endpoint: OBDConnectionEndpoint) async throws -> [OBDPIDRequestTransportObservation] {
        readCount += 1
        guard let request = requests.first, !outcomes.isEmpty else { return [] }
        return [OBDPIDRequestTransportObservation(request: request, outcome: outcomes.removeFirst())]
    }

    /// 未使用の辞書型readを空応答として実装します。
    ///
    /// 責務: protocol互換要件を満たしtyped読取testへ影響しない空辞書を返します。
    /// - Returns: 常に空の応答辞書。
    func read(_ requests: [OBDPIDRequest], using endpoint: OBDConnectionEndpoint) async throws -> [OBDPIDRequest: [UInt8]] { [:] }
}

/// deterministicな単調時刻列を供給します。
private final class MonotonicSequence: @unchecked Sendable {
    /// 未返却の単調値です。
    private var values: [UInt64]

    /// 返却順の単調値を固定します。
    ///
    /// 責務: test clockの有限な値列を初期化します。
    /// - Parameter values: 呼出し順に返す値。
    init(values: [UInt64]) { self.values = values }

    /// 次の単調値を返します。
    ///
    /// 責務: 値列の先頭を1回だけ消費します。
    /// - Returns: 次の値、または枯渇時の0。
    func next() -> UInt64 { values.isEmpty ? 0 : values.removeFirst() }
}
