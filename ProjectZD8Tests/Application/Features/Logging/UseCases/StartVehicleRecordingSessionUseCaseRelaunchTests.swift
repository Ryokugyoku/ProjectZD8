import Foundation
import XCTest
@testable import ProjectZD8

/// プロセス復帰後に続行可能なセッションがある時、`StartVehicleRecordingSessionUseCase` が
/// 「開始 → 車両確定または未登録の確定 → 進行中かを確認 → 観測VIN」の順で送り、続行したセッションを開始成功として扱うことを検証します。
///
/// 続行可能なセッションがある間、開始要求だけでは現在セッションが決まりません(確定で続行か新規かが決まる)。
@MainActor
final class StartVehicleRecordingSessionUseCaseRelaunchTests: XCTestCase {
    /// 型名を短く参照するための別名です。
    private typealias Fixture = ConnectionSessionAcquisitionRecorderFixture
    /// 観測VINです。
    private static let vin = "JF1ZD8A11P9000001"
    /// 最後にcommitしたRawの実時刻です。
    private let lastCommittedAt = Date(timeIntervalSince1970: 1_020)
    /// 登録済みの車両です。
    private let vehicle = VehicleProfile(
        id: VehicleID(rawValue: UUID(uuidString: "21111111-2222-3333-4444-555555555555")!),
        vin: StartVehicleRecordingSessionUseCaseRelaunchTests.vin,
        name: "BRZ"
    )
    /// 記録に使う接続終端です。
    private let endpoint = OBDConnectionEndpoint(transport: .bluetoothLowEnergy, systemIdentifier: "id", displayName: "A")

    /// 登録済み車両のセッションは、猶予内に同じ車両の記録を始めると続行し、開始成功になります。
    ///
    /// 責務: 車両確定の後で進行中かを確かめるため、続行したセッションで `true` を返し、セッションが終了しないことを確認します。
    func testRegisteredResumableSessionContinuesAndReportsStarted() async throws {
        let (fixture, model) = try await relaunchedModel(sessionVehicle: vehicle)

        let started = StartVehicleRecordingSessionUseCase(lifecycle: model).execute(request(vehicle: vehicle, observedVIN: nil))

        XCTAssertTrue(started)
        XCTAssertEqual(model.activeSession?.id, fixture.sessionID)
        XCTAssertNil(try stored(fixture).endedAt)
    }

    /// 未登録車両のセッションは、猶予内に車両なしの記録を始めると続行し、続行したセッションへ観測VINを保存します。
    ///
    /// 責務: 未登録の確定を送ってから観測VINを送ることで、続行したセッションに観測VINが残ることを確認します。
    func testUnregisteredResumableSessionContinuesAndRecordsObservedVIN() async throws {
        let (fixture, model) = try await relaunchedModel(sessionVehicle: nil)

        let started = StartVehicleRecordingSessionUseCase(lifecycle: model).execute(request(vehicle: nil, observedVIN: Self.vin))

        XCTAssertTrue(started)
        XCTAssertEqual(model.activeSession?.id, fixture.sessionID)
        XCTAssertEqual(model.activeSession?.observedVIN, Self.vin)
        XCTAssertEqual(try stored(fixture).observedVIN, Self.vin)
    }

    /// 未登録車両のセッションは、登録済み車両の記録では続けず、元のセッションを終了して新しいセッションで開始成功になります。
    ///
    /// 責務: 確定で新規と決まった場合も `true` を返し、新しいセッションに車両が入ることを確認します。
    func testUnregisteredResumableSessionIsReplacedByRegisteredRecording() async throws {
        let (fixture, model) = try await relaunchedModel(sessionVehicle: nil)

        let started = StartVehicleRecordingSessionUseCase(lifecycle: model).execute(request(vehicle: vehicle, observedVIN: nil))

        XCTAssertTrue(started)
        XCTAssertNotEqual(model.activeSession?.id, fixture.sessionID)
        XCTAssertEqual(model.activeSession?.vehicle?.id, vehicle.id)
        XCTAssertEqual(try stored(fixture).endedAt, lastCommittedAt)
    }

    /// 続行か新規かが決まる前(開始要求だけを送った状態)は、観測VINも観測VINによる車両の関連付けも何もしません。
    ///
    /// 責務: 確定の前に送られた `vinObserved` と `observedVINVehicleRegistered` が、続行したセッションへ反映されないことを確認します。
    func testObservedVINBeforeResumptionDecisionIsIgnored() async throws {
        let (fixture, model) = try await relaunchedModel(sessionVehicle: nil)
        model.send(.startRequested)
        XCTAssertNil(model.activeSession)

        model.send(.vinObserved(Self.vin))
        model.send(.observedVINVehicleRegistered(vehicle))
        model.send(.vehicleUnregistered)

        XCTAssertEqual(model.activeSession?.id, fixture.sessionID)
        XCTAssertNil(model.activeSession?.observedVIN)
        XCTAssertNil(model.activeSession?.vehicle)
        XCTAssertNil(try stored(fixture).observedVIN)
    }

    // MARK: - Helpers

    /// 記録開始要求を作ります。
    ///
    /// 責務: 指定の車両と観測VINを持ち、型式コード・判定結果のない要求を返します。
    /// - Parameters:
    ///   - vehicle: 確定する車両。
    ///   - observedVIN: 観測VIN。
    /// - Returns: 記録開始要求。
    private func request(vehicle: VehicleProfile?, observedVIN: String?) -> VehicleRecordingStartRequest {
        VehicleRecordingStartRequest(endpoint: endpoint, vehicle: vehicle, observedVIN: observedVIN, vehicleModelCode: nil, adapterProbeEvidence: nil)
    }

    /// 2周回をcommitして終了せずに止まったセッションを作り、猶予内にアカウントを有効化したモデルを返します。
    ///
    /// 責務: セッションの車両を指定してから記録し、プロセス復帰後の続行待ちの状態を作ります。
    /// - Parameter sessionVehicle: 中断したセッションの車両。`nil` なら車両なし。
    /// - Returns: GRDBの部品と、続行可能なセッションを持つモデル。
    /// - Throws: 記録または保存の失敗。
    private func relaunchedModel(sessionVehicle: VehicleProfile?) async throws -> (Fixture, ConnectionSessionLifecycleModel) {
        let fixture = try Fixture(storage: .grdb)
        var session = try stored(fixture)
        session.vehicle = sessionVehicle.map(ConnectionSessionVehicle.init(profile:))
        try fixture.sessions.save(session)
        try await fixture.start()
        fixture.dates.set(Date(timeIntervalSince1970: 1_010))
        try await fixture.respondedRound(0, payload: 10)
        fixture.dates.set(lastCommittedAt)
        try await fixture.respondedRound(1, payload: 20)
        try await fixture.recorder.flush(.backgroundTransition, generation: 1)
        let dates = ManualDateClock(lastCommittedAt.addingTimeInterval(30))
        let model = ConnectionSessionLifecycleModel(
            repository: fixture.sessions,
            rawLogRepository: fixture.sessions,
            acquisitionTerminationRepository: fixture.acquisition,
            now: { dates.now() },
            recoverRelaunchedSession: RecoverRelaunchedConnectionSessionUseCase(
                rawLogRepository: fixture.sessions, segmentRepository: fixture.segments,
                gapRepository: fixture.gaps, terminationRepository: fixture.acquisition
            )
        )
        model.send(.accountIdentifierChanged("account"))
        XCTAssertNil(model.activeSession)
        return (fixture, model)
    }

    /// 部品のセッションを読み戻します。
    ///
    /// 責務: 部品のセッションIDのセッションを返します。
    /// - Parameter fixture: GRDBの部品。
    /// - Returns: セッション。
    /// - Throws: 読込失敗、またはセッションが無い場合のエラー。
    private func stored(_ fixture: Fixture) throws -> ConnectionSession {
        try XCTUnwrap(fixture.sessions.sessions(for: "account").first { $0.id == fixture.sessionID })
    }
}
