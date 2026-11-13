import Foundation
import XCTest
@testable import ProjectZD8

/// Production LiveTelemetry loopから取得証拠portまでの順序とidentityを検証します。
@MainActor
final class LiveTelemetryProductionAcquisitionTests: XCTestCase {
    /// manifest start後にだけbatchを開始し、tickとordinalを同じ順序で増加させます。
    ///
    /// 責務: Production polling loopが1 tickを1 stable batch identityへ対応付けることを確認します。
    func testPollingStartsEvidenceBeforeStableBatchOrdinals() async {
        let evidence = LiveTelemetryAcquisitionEvidenceSpy()
        let model = makeModel(evidence: evidence)

        model.send(.startRequested(endpoint, vehicleID, vehicleModelCode: nil))
        for _ in 0..<100 {
            if await evidence.batchInputs.count >= 2 { break }
            try? await Task.sleep(for: .milliseconds(10))
        }

        let events = await evidence.events
        let batches = await evidence.batchInputs
        XCTAssertEqual(events.prefix(3), [.start, .batch, .batch])
        XCTAssertEqual(batches.prefix(2).map(\.batchOrdinal), [0, 1])
        XCTAssertEqual(batches.prefix(2).map(\.policyTick), [0, 1])
        model.send(.stopRequested)
        for _ in 0..<100 where model.state.phase != .idle {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    /// manifest開始失敗時はbatch取得を1件も許可しません。
    ///
    /// 責務: Production polling loopのmanifest保存失敗をphysical batch 0件の取得失敗へ変換します。
    func testManifestFailurePreventsEveryBatchDispatch() async {
        let evidence = LiveTelemetryAcquisitionEvidenceSpy(failsStart: true)
        var endReasons: [ConnectionSessionEndReason] = []
        let model = makeModel(evidence: evidence) { endReasons.append($0) }

        model.send(.startRequested(endpoint, vehicleID, vehicleModelCode: nil))
        for _ in 0..<100 where model.state.phase != .failed {
            await Task.yield()
        }

        let batchCount = await evidence.batchInputs.count
        XCTAssertEqual(batchCount, 0)
        XCTAssertEqual(endReasons, [.acquisitionFailed])
    }

    /// 250 ms sleepの予定wakeからの超過だけを後続batchへ渡します。
    ///
    /// 責務: tick 0を未計測、tick 1を10 ms遅延として匿名schedule contextへ変換することを確認します。
    func testPollingRecordsDelayBeyondScheduledWake() async {
        let evidence = LiveTelemetryAcquisitionEvidenceSpy()
        let clock = LiveTelemetryMonotonicClock(values: [1_000_000_000, 1_260_000_000])
        let model = makeModel(evidence: evidence, monotonicNanoseconds: clock.next)

        model.send(.startRequested(endpoint, vehicleID, vehicleModelCode: nil))
        for _ in 0..<100 {
            if await evidence.batchInputs.count >= 2 { break }
            try? await Task.sleep(for: .milliseconds(10))
        }

        let batches = await evidence.batchInputs
        XCTAssertEqual(batches.prefix(2).map(\.scheduleDelayNanoseconds), [nil, 10_000_000])
        model.send(.stopRequested)
        for _ in 0..<100 where model.state.phase != .idle {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    /// Production相当の定義、保存済みcapability、取得証拠portをモデルへ注入します。
    ///
    /// 責務: capability discovery通信を発生させないProduction polling fixtureを構築します。
    /// - Parameters:
    ///   - evidence: manifestとbatch呼出しを記録するport。
    ///   - monotonicNanoseconds: sleep前後の単調時刻を返すclock。
    ///   - sessionDidEnd: 取得終了理由の通知先。
    /// - Returns: 方式B経路を使用するLiveTelemetry model。
    private func makeModel(
        evidence: LiveTelemetryAcquisitionEvidenceSpy,
        monotonicNanoseconds: @escaping @Sendable () -> UInt64 = { DispatchTime.now().uptimeNanoseconds },
        sessionDidEnd: @escaping @MainActor (ConnectionSessionEndReason) -> Void = { _ in }
    ) -> LiveTelemetryModel {
        let definitionRepository = LiveTelemetryProductionDefinitionRepository()
        return LiveTelemetryModel(
            readMajorPIDs: ReadMajorOBDPIDsUseCase(
                definitionRepository: definitionRepository,
                telemetry: LiveTelemetryProductionCapabilityTelemetry()
            ),
            loadVehicleCapabilities: LoadVehiclePIDCapabilitiesUseCase(
                repository: LiveTelemetryProductionCapabilityRepository(vehicleID: vehicleID),
                telemetry: LiveTelemetryProductionCapabilityTelemetry(),
                definitionRepository: definitionRepository
            ),
            acquisitionEvidence: evidence,
            monotonicNanoseconds: monotonicNanoseconds,
            sessionDidEnd: sessionDidEnd
        )
    }

    /// test用OBD終端です。
    private var endpoint: OBDConnectionEndpoint {
        OBDConnectionEndpoint(
            transport: .serial,
            systemIdentifier: "phase4g-live-loop",
            displayName: "Phase 4G live loop"
        )
    }

    /// test用登録車両IDです。
    private var vehicleID: VehicleID {
        VehicleID(rawValue: UUID(uuidString: "10000000-0000-0000-0000-000000000004")!)
    }
}

/// testが指定した単調時刻をthread-safeに返します。
private final class LiveTelemetryMonotonicClock: @unchecked Sendable {
    /// 値列への並行アクセスを直列化します。
    private let lock = NSLock()
    /// 次回以降に返す単調時刻です。
    private var values: [UInt64]

    /// 返却する単調時刻列を固定します。
    ///
    /// 責務: polling schedule遅延testのclock入力を順序付きで初期化します。
    /// - Parameter values: 呼出し順に返す単調時刻。
    init(values: [UInt64]) { self.values = values }

    /// 次の単調時刻を返します。
    ///
    /// 責務: 並行安全に先頭時刻を1件消費し、欠落時は直前相当の0を返します。
    /// - Returns: 次の固定単調時刻、または値列が空の場合は0。
    func next() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return values.isEmpty ? 0 : values.removeFirst()
    }
}

/// Production取得証拠portの呼出し種別です。
private enum LiveTelemetryAcquisitionEvidenceEvent: Equatable {
    /// manifest開始要求です。
    case start
    /// batch取得要求です。
    case batch
    /// 世代取消要求です。
    case cancel
}

/// manifestとbatchの呼出し順を保持する取得証拠spyです。
private actor LiveTelemetryAcquisitionEvidenceSpy: LiveTelemetryAcquisitionEvidencePort {
    /// manifest開始を失敗させるかを示します。
    private let failsStart: Bool
    /// 観測した呼出し順です。
    private(set) var events: [LiveTelemetryAcquisitionEvidenceEvent] = []
    /// 観測したbatch入力です。
    private(set) var batchInputs: [LiveTelemetryAcquisitionBatchInput] = []

    /// manifest開始結果を固定します。
    ///
    /// 責務: Production polling testの開始成否を初期化します。
    /// - Parameter failsStart: `true` の場合にmanifest開始を失敗させます。
    init(failsStart: Bool = false) { self.failsStart = failsStart }

    /// manifest開始要求を記録します。
    ///
    /// 責務: 取得開始順を記録し、指定時だけ保存失敗を返します。
    /// - Parameter input: 取得開始入力。
    /// - Throws: `failsStart` の場合は保存先利用不能。
    func start(_ input: LiveTelemetryAcquisitionStartInput) async throws {
        events.append(.start)
        if failsStart { throw ConnectionSessionAcquisitionRepositoryError.unavailable }
    }

    /// batch入力を記録して固定sampleを返します。
    ///
    /// 責務: polling tickとordinalを記録可能な表示用sampleへ変換します。
    /// - Parameter input: Production loopが割り当てたbatch入力。
    /// - Returns: 入力先頭定義に対応する固定sample。
    func acquire(_ input: LiveTelemetryAcquisitionBatchInput) async throws -> [OBDPIDSample] {
        events.append(.batch)
        batchInputs.append(input)
        guard let definition = input.definitions.first else { return [] }
        return [
            OBDPIDSample(
                request: OBDPIDRequest(service: definition.service, pid: definition.pid),
                nameKey: definition.nameKey,
                value: 42,
                unit: definition.unit,
                vehicleModelCode: definition.vehicleModelCode,
                observedAt: input.startedAt,
                summaryKey: definition.summaryKey,
                highValueKey: definition.highValueKey,
                lowValueKey: definition.lowValueKey,
                correlationKey: definition.correlationKey
            )
        ]
    }

    /// 世代取消しを記録します。
    ///
    /// 責務: polling停止を取得証拠portの取消eventへ変換します。
    /// - Parameter generation: 取消対象世代。
    func cancel(generation: UInt) async { events.append(.cancel) }
}

/// Production polling test用の固定PID定義を返します。
private struct LiveTelemetryProductionDefinitionRepository: OBDPIDDefinitionRepository {
    /// 空状態の定義repositoryを生成します。
    ///
    /// 責務: 固定定義供給境界を初期化します。
    init() {}

    /// 数値化可能なPID定義を返します。
    ///
    /// 責務: Production polling testへ完全range付き定義を1件供給します。
    /// - Returns: Service 01 PID 0Cの固定定義。
    func definitions() throws -> [OBDPIDDefinition] {
        [OBDPIDDefinition(
            service: 1,
            pid: 12,
            nameKey: "test.phase4g.pid",
            requiredByteCount: 1,
            formula: "A",
            unit: "unit",
            minimumValue: 0,
            maximumValue: 255,
            sourceURI: "test://phase4g-live-loop",
            revision: 1
        )]
    }

    /// test対象外の保存を受理します。
    ///
    /// 責務: 未使用の定義保存要求を変更なしで完了します。
    /// - Parameter definition: testでは使用しない定義。
    func upsert(_ definition: OBDPIDDefinition) throws {}

    /// test対象外の単一照会へ未登録を返します。
    ///
    /// 責務: 未使用の単一定義照会を `nil` へ変換します。
    /// - Returns: 常に `nil`。
    func definition(service: UInt8, pid: UInt8) throws -> OBDPIDDefinition? { nil }
}

/// 保存済みcapabilityを返すrepositoryです。
private struct LiveTelemetryProductionCapabilityRepository: VehiclePIDCapabilityRepository {
    /// capabilityを所有する車両IDです。
    let vehicleID: VehicleID

    /// 車両IDを固定します。
    ///
    /// 責務: 保存済みcapabilityの所有車両を初期化します。
    /// - Parameter vehicleID: capabilityを所有する車両ID。
    init(vehicleID: VehicleID) { self.vehicleID = vehicleID }

    /// 保存済みcapabilityを返します。
    ///
    /// 責務: 対象車両を収集有効な確認済みPIDへ変換します。
    /// - Parameter vehicleID: 照会対象車両ID。
    /// - Returns: Service 01 PID 0Cの保存済みcapability。
    func capabilities(for vehicleID: VehicleID) throws -> [VehiclePIDCapability] {
        [VehiclePIDCapability(
            vehicleID: self.vehicleID,
            request: OBDPIDRequest(service: 1, pid: 12),
            isCollectionEnabled: true,
            discoveredAt: Date(timeIntervalSince1970: 1)
        )]
    }

    /// 初回保存をtest対象外として拒否します。
    ///
    /// 責務: 想定外のcapability discovery保存を明示失敗へ変換します。
    /// - Parameters:
    ///   - capabilities: testでは保存しないcapability群。
    ///   - vehicleID: testでは保存しない対象車両ID。
    /// - Throws: 常に無効状態エラー。
    func insertInitial(_ capabilities: [VehiclePIDCapability], for vehicleID: VehicleID) throws {
        throw ConnectionSessionRepositoryError.invalidState
    }

    /// 追加発見保存をtest対象外として拒否します。
    ///
    /// 責務: 想定外のcapability追加を明示失敗へ変換します。
    /// - Parameters:
    ///   - capabilities: testでは追加しないcapability群。
    ///   - vehicleID: testでは追加しない対象車両ID。
    /// - Throws: 常に無効状態エラー。
    func mergeDiscovered(_ capabilities: [VehiclePIDCapability], for vehicleID: VehicleID) throws {
        throw ConnectionSessionRepositoryError.invalidState
    }

    /// 収集選択更新をtest対象外として拒否します。
    ///
    /// 責務: 想定外の収集選択更新を明示失敗へ変換します。
    /// - Parameters:
    ///   - isEnabled: testでは保存しない収集有効状態。
    ///   - request: testでは更新しないService/PID。
    ///   - vehicleID: testでは更新しない対象車両ID。
    /// - Throws: 常に無効状態エラー。
    func setCollectionEnabled(
        _ isEnabled: Bool,
        for request: OBDPIDRequest,
        vehicleID: VehicleID
    ) throws {
        throw ConnectionSessionRepositoryError.invalidState
    }
}

/// capability探索では呼ばれない通信境界です。
private actor LiveTelemetryProductionCapabilityTelemetry: OBDPIDTelemetryPort {
    /// 空状態の通信境界を生成します。
    ///
    /// 責務: 保存済みcapability test用の非通信境界を初期化します。
    init() {}

    /// 想定外の物理要求を失敗させます。
    ///
    /// 責務: capability discovery通信が発生していないことを明示失敗で監視します。
    func read(_ requests: [OBDPIDRequest], using endpoint: OBDConnectionEndpoint) async throws -> [OBDPIDRequest: [UInt8]] {
        throw OBDPIDTelemetryError.unavailable
    }
}
