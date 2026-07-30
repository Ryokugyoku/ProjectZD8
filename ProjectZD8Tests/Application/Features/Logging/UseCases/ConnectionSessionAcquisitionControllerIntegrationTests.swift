import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// file-backed Production GRDBとfake typed transportによる方式B接続を検証します。
@MainActor
final class ConnectionSessionAcquisitionControllerIntegrationTests: XCTestCase {
    /// manifest保存後だけ物理要求を許可し、同じ応答をRawとsampleへ変換します。
    ///
    /// 責務: Production storage、manifest gate、typed transport、方式B batchの一連接続を確認します。
    func testManifestGatePrecedesTransportAndPersistsRespondedBatch() async throws {
        let fixture = try makeFixture(outcomes: [.responded([42])])

        try await fixture.controller.start(fixture.startInput)
        let countBeforeAcquire = await fixture.telemetry.readCount
        XCTAssertEqual(countBeforeAcquire, 0)

        let samples = try await fixture.controller.acquire(fixture.batchInput(ordinal: 0, tick: 0))

        let countAfterAcquire = await fixture.telemetry.readCount
        XCTAssertEqual(countAfterAcquire, 1)
        XCTAssertEqual(samples.map(\.value), [42])
        XCTAssertEqual(try fixture.storage.entries(for: fixture.session.id).map(\.payload), [[42]])
        let batches = try fixture.storage.batches(for: fixture.session.id)
        XCTAssertEqual(batches.map(\.identity.ordinal), [0])
        XCTAssertEqual(batches.map(\.policyTick), [0])
        XCTAssertEqual(batches[0].requests.map(\.transportOutcome), [.responded])
    }

    /// session不在ではmanifest保存と物理要求を開始しません。
    ///
    /// 責務: 親session欠落を最初のphysical requestより前の失敗へ変換します。
    func testMissingSessionPreventsEveryPhysicalRequest() async throws {
        let fixture = try makeFixture(outcomes: [.responded([42])], exposesActiveSession: false)

        do {
            try await fixture.controller.start(fixture.startInput)
            XCTFail("session不在の開始が成功しました")
        } catch {}

        let readCount = await fixture.telemetry.readCount
        XCTAssertEqual(readCount, 0)
        XCTAssertTrue(try fixture.storage.entries(for: fixture.session.id).isEmpty)
    }

    /// timeoutはRawを作らずterminal evidenceだけを保存します。
    ///
    /// 責務: typed timeoutをRaw 0件のfailed batchへ変換します。
    func testTimeoutPersistsNoRawAndSealsBatch() async throws {
        let fixture = try makeFixture(outcomes: [.timedOut])
        try await fixture.controller.start(fixture.startInput)

        let samples = try await fixture.controller.acquire(fixture.batchInput(ordinal: 0, tick: 0))

        XCTAssertTrue(samples.isEmpty)
        XCTAssertTrue(try fixture.storage.entries(for: fixture.session.id).isEmpty)
        let batch = try XCTUnwrap(fixture.storage.batches(for: fixture.session.id).first)
        XCTAssertEqual(batch.completionState, .failed)
        XCTAssertEqual(batch.requests[0].transportOutcome, .timedOut)
    }

    /// 完了済みbatchのexact retryは再送せずcanonical結果を再利用します。
    ///
    /// 責務: 同じordinal、tick、開始時刻のretryがRawまたはterminal evidenceを重複させないことを確認します。
    func testExactBatchRetryDoesNotRedispatchOrDuplicateRaw() async throws {
        let fixture = try makeFixture(outcomes: [.responded([42]), .responded([99])])
        try await fixture.controller.start(fixture.startInput)
        let input = fixture.batchInput(ordinal: 0, tick: 0)
        _ = try await fixture.controller.acquire(input)

        let retriedSamples = try await fixture.controller.acquire(input)

        XCTAssertTrue(retriedSamples.isEmpty)
        let readCount = await fixture.telemetry.readCount
        XCTAssertEqual(readCount, 1)
        XCTAssertEqual(try fixture.storage.entries(for: fixture.session.id).map(\.payload), [[42]])
        XCTAssertEqual(try fixture.storage.batches(for: fixture.session.id).count, 1)
    }

    /// controller、transport、GRDB writeが同じ匿名event境界へ順序付きで到達します。
    ///
    /// 責務: Production方式Bの開始からbatch確定までに必要な区間とDB Queue通過点が欠落しないことを確認します。
    func testPerformanceEventsCoverControllerTransportAndDatabaseQueue() async throws {
        let fixture = try makeFixture(outcomes: [.responded([42])])

        try await fixture.controller.start(fixture.startInput)
        _ = try await fixture.controller.acquire(fixture.batchInput(ordinal: 0, tick: 0))

        let events = fixture.performanceEvents.snapshot()
        XCTAssertEqual(events.first, .begin(.acquisitionStart))
        XCTAssertTrue(events.contains(.queue(.manifestPersistence)))
        XCTAssertTrue(events.contains(.begin(.batchAcquisition)))
        XCTAssertTrue(events.contains(.queue(.batchOpenPersistence)))
        XCTAssertTrue(events.contains(.end(.requestTransport, .succeeded)))
        XCTAssertTrue(events.contains(.queue(.respondedPersistence)))
        XCTAssertTrue(events.contains(.queue(.batchSealPersistence)))
        XCTAssertEqual(events.last, .end(.batchAcquisition, .succeeded))
    }

    /// start前のstale batch拒否と世代取消を独立eventとして記録します。
    ///
    /// 責務: 性能測定でstale拒否件数と明示取消件数を匿名操作別に集計できることを確認します。
    func testPerformanceEventsDistinguishStaleRejectionAndCancellation() async throws {
        let fixture = try makeFixture(outcomes: [])

        do {
            _ = try await fixture.controller.acquire(fixture.batchInput(ordinal: 0, tick: 0))
            XCTFail("start前のbatch取得が成功しました")
        } catch {
            XCTAssertEqual(error as? PersistAcquisitionBatchError, .inactiveGeneration)
        }
        await fixture.controller.cancel(generation: 1)

        let events = fixture.performanceEvents.snapshot()
        XCTAssertTrue(events.contains(.end(.staleBatchRejection, .failed)))
        XCTAssertTrue(events.contains(.end(.generationCancellation, .succeeded)))
    }

    /// test依存を同じfile-backed Queueへ構築します。
    ///
    /// 責務: Production storageとfake typed transportを1件のlocal integration fixtureへまとめます。
    /// - Parameters:
    ///   - outcomes: 物理要求順に返すtyped結果。
    ///   - exposesActiveSession: controllerへ親sessionを公開するか。
    /// - Returns: manifest開始とbatch取得を実行できるfixture。
    private func makeFixture(
        outcomes: [OBDPIDRequestTransportOutcome],
        exposesActiveSession: Bool = true
    ) throws -> ControllerIntegrationFixture {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let queue = try DatabaseQueue(path: directory.appending(path: "integration.sqlite").path)
        let performanceEvents = ControllerIntegrationPerformanceEventSpy()
        let storage = try GRDBConnectionSessionRepository(
            databaseQueue: queue,
            performanceEvents: performanceEvents
        )
        let session = ConnectionSession(
            id: ConnectionSessionID(rawValue: UUID()),
            accountIdentifier: "phase4g-account",
            startedAt: Date(timeIntervalSince1970: 1)
        )
        try storage.save(session)
        let telemetry = ControllerIntegrationTelemetry(outcomes: outcomes)
        let definition = OBDPIDDefinition(
            service: 1,
            pid: 12,
            nameKey: "test.pid",
            requiredByteCount: 1,
            formula: "A",
            unit: "unit",
            minimumValue: 0,
            maximumValue: 255,
            sourceURI: "test://phase4g",
            revision: 1
        )
        let controller = ConnectionSessionAcquisitionController(
            createManifest: CreateConnectionSessionAcquisitionManifestUseCase(
                acquisitionRepository: storage,
                evidencePort: ControllerIntegrationEvidencePort()
            ),
            persistBatch: PersistAcquisitionBatchUseCase(
                repository: storage,
                telemetry: telemetry,
                now: { Date(timeIntervalSince1970: 20) },
                monotonicNanoseconds: ControllerIntegrationClock().next,
                performanceEvents: performanceEvents
            ),
            activeSessionID: { exposesActiveSession ? session.id : nil },
            manifestVersion: 1,
            pollingPolicyVersion: 1,
            modelInputManifestVersion: 1,
            formulaCanonicalizationVersion: 1,
            performanceEvents: performanceEvents
        )
        return ControllerIntegrationFixture(
            storage: storage,
            telemetry: telemetry,
            performanceEvents: performanceEvents,
            controller: controller,
            session: session,
            definition: definition
        )
    }
}

/// controller local integrationの依存と入力を保持します。
private struct ControllerIntegrationFixture {
    /// session、Raw、取得証拠が同じQueueを使うProduction storageです。
    let storage: GRDBConnectionSessionRepository
    /// typed結果と送信回数を保持するfake transportです。
    let telemetry: ControllerIntegrationTelemetry
    /// controller、transport、GRDB Queueの匿名性能event記録先です。
    let performanceEvents: ControllerIntegrationPerformanceEventSpy
    /// Production loop用の取得証拠controllerです。
    let controller: ConnectionSessionAcquisitionController
    /// 親接続sessionです。
    let session: ConnectionSession
    /// manifestとbatchで使用するPID定義です。
    let definition: OBDPIDDefinition

    /// manifest開始入力を返します。
    var startInput: LiveTelemetryAcquisitionStartInput {
        LiveTelemetryAcquisitionStartInput(
            generation: 1,
            definitions: [definition],
            capabilities: [
                ConnectionSessionAcquisitionPIDCapabilityInput(
                    request: OBDPIDRequest(service: definition.service, pid: definition.pid),
                    support: .supported,
                    isCollectionEnabled: true
                )
            ],
            orderedRequests: [OBDPIDRequest(service: definition.service, pid: definition.pid)]
        )
    }

    /// 指定identityのbatch入力を返します。
    ///
    /// 責務: ordinalとpolicy tickを同じ固定開始時刻のbatch入力へ変換します。
    /// - Parameters:
    ///   - ordinal: session内batch番号。
    ///   - tick: polling policy tick。
    /// - Returns: controllerへ渡せるbatch入力。
    func batchInput(ordinal: Int64, tick: UInt) -> LiveTelemetryAcquisitionBatchInput {
        LiveTelemetryAcquisitionBatchInput(
            generation: 1,
            batchOrdinal: ordinal,
            policyTick: tick,
            startedAt: Date(timeIntervalSince1970: 10 + Double(ordinal)),
            definitions: [definition],
            endpoint: OBDConnectionEndpoint(
                transport: .serial,
                systemIdentifier: "phase4g-fake",
                displayName: "Phase 4G fake"
            )
        )
    }
}

/// integration testが観測する匿名performance eventです。
private enum ControllerIntegrationPerformanceEvent: Equatable {
    /// 区間開始です。
    case begin(AcquisitionPerformanceOperation)
    /// DB Queue通過です。
    case queue(AcquisitionPerformanceOperation)
    /// 結果付き区間終了です。
    case end(AcquisitionPerformanceOperation, AcquisitionPerformanceOutcome)
}

/// controller、transport、GRDBが通知したperformance eventをthread-safeに保持します。
private final class ControllerIntegrationPerformanceEventSpy: @unchecked Sendable, AcquisitionPerformanceEventPort {
    /// event列と採番への並行アクセスを直列化します。
    private let lock = NSLock()
    /// 次に割り当てる匿名interval番号です。
    private var nextIdentifier: UInt64 = 1
    /// 観測済みevent列です。
    private var events: [ControllerIntegrationPerformanceEvent] = []

    /// 空のevent記録先を生成します。
    ///
    /// 責務: integration test用の匿名performance event列を初期化します。
    init() {}

    /// 区間開始を記録して匿名tokenを返します。
    ///
    /// 責務: 1件の開始通知を順序付きeventと一意なtest tokenへ変換します。
    /// - Parameters:
    ///   - operation: 計測する操作。
    ///   - context: 匿名取得位置。
    /// - Returns: Queue通過と終了に再利用するtoken。
    func begin(
        _ operation: AcquisitionPerformanceOperation,
        context: AcquisitionPerformanceContext
    ) -> AcquisitionPerformanceInterval {
        lock.lock()
        defer { lock.unlock() }
        let interval = AcquisitionPerformanceInterval(
            identifier: nextIdentifier,
            operation: operation,
            context: context
        )
        nextIdentifier += 1
        events.append(.begin(operation))
        return interval
    }

    /// DB Queue通過を記録します。
    ///
    /// 責務: 1件のQueue通過通知を開始済み操作の順序付きeventへ変換します。
    /// - Parameter interval: 開始済み区間。
    func queueDidEnter(_ interval: AcquisitionPerformanceInterval) {
        append(.queue(interval.operation))
    }

    /// 区間終了を結果付きで記録します。
    ///
    /// 責務: 1件の終了通知を操作と結果を保持する順序付きeventへ変換します。
    /// - Parameters:
    ///   - interval: 開始済み区間。
    ///   - outcome: 完了結果。
    func end(
        _ interval: AcquisitionPerformanceInterval,
        outcome: AcquisitionPerformanceOutcome
    ) {
        append(.end(interval.operation, outcome))
    }

    /// 現在のevent列を返します。
    ///
    /// 責務: 並行書込み中の内部列を安定したtest検証用snapshotへ変換します。
    /// - Returns: 呼出し時点のevent列。
    func snapshot() -> [ControllerIntegrationPerformanceEvent] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }

    /// eventを末尾へ追加します。
    ///
    /// 責務: 1件のperformance eventをlock保護下の観測列へ追加します。
    /// - Parameter event: 追加するevent。
    private func append(_ event: ControllerIntegrationPerformanceEvent) {
        lock.lock()
        defer { lock.unlock() }
        events.append(event)
    }
}

/// typed結果を要求順に返すfake transportです。
private actor ControllerIntegrationTelemetry: OBDPIDTelemetryPort {
    /// 未返却のtyped結果です。
    private var outcomes: [OBDPIDRequestTransportOutcome]
    /// 実行したphysical request数です。
    private(set) var readCount = 0

    /// typed結果列を固定します。
    ///
    /// 責務: local integrationで返すtransport結果順を初期化します。
    /// - Parameter outcomes: physical request順に返す結果。
    init(outcomes: [OBDPIDRequestTransportOutcome]) { self.outcomes = outcomes }

    /// 1件の要求へ次のtyped結果を返します。
    ///
    /// 責務: 物理送信相当の呼出しを数え、次の排他観測へ変換します。
    /// - Parameters:
    ///   - requests: 実行対象要求。
    ///   - endpoint: testでは使用しない終端。
    /// - Returns: 先頭要求と次のtyped結果の観測。
    func readObservations(
        _ requests: [OBDPIDRequest],
        using endpoint: OBDConnectionEndpoint
    ) async throws -> [OBDPIDRequestTransportObservation] {
        readCount += requests.count
        guard let request = requests.first, !outcomes.isEmpty else { return [] }
        return [.init(request: request, outcome: outcomes.removeFirst())]
    }

    /// 辞書型readをtest対象外の空結果として実装します。
    ///
    /// 責務: protocol互換の辞書型読取を副作用のない空結果へ変換します。
    /// - Returns: 常に空辞書。
    func read(_ requests: [OBDPIDRequest], using endpoint: OBDConnectionEndpoint) async throws -> [OBDPIDRequest: [UInt8]] { [:] }
}

/// 固定のProduction相当runtime evidenceを返します。
private struct ControllerIntegrationEvidencePort: ConnectionSessionAcquisitionEvidencePort {
    /// runtime evidence fixtureを生成します。
    ///
    /// 責務: local integration用の固定app/build/schema/platformを構築します。
    init() {}

    /// 固定runtime evidenceを返します。
    ///
    /// 責務: manifest作成を実環境へ依存しない決定的なversion証拠へ変換します。
    /// - Returns: Phase 4G local integration用runtime evidence。
    func evidence() async throws -> ConnectionSessionAcquisitionRuntimeEvidence {
        ConnectionSessionAcquisitionRuntimeEvidence(
            applicationVersion: try AcquisitionApplicationVersion(
                marketingVersion: "phase4g",
                buildVersion: "local"
            ),
            schemaContractVersion: 1,
            acquisitionPlatform: .macOS
        )
    }
}

/// 単調増加するrequest clockです。
private final class ControllerIntegrationClock: @unchecked Sendable {
    /// 次回返す値です。
    private var value: UInt64 = 0

    /// 0始まりのclockを生成します。
    ///
    /// 責務: local integration用の単調clockを初期化します。
    init() {}

    /// 次の単調値を返します。
    ///
    /// 責務: 呼出しごとに100増加する時刻を1件返します。
    /// - Returns: 現在値。
    func next() -> UInt64 {
        defer { value += 100 }
        return value
    }
}
