import XCTest
@testable import ProjectZD8

/// `AdapterLinkSupervisionOperationRunner` を直接使い、`AdapterLinkSupervisionUseCase*Tests` では通らない分岐
/// (待機の失敗、取り消しの無い置き換え、取り消し後の新しい操作)を検証します。
///
/// 初期化・確認・VIN読取の成功/失敗の変換と、リンク断・再接続後の古い結果の破棄は、
/// 状態機械を通した `AdapterLinkSupervisionUseCaseVehicleConfirmationTests` と `…StaleResultTests` で検証済みのため重複させません。
@MainActor
final class AdapterLinkSupervisionOperationRunnerTests: XCTestCase {
    /// 初期化ポートの fake です。
    private let initialization = AdapterLinkInitializationFake()
    /// 車両確認ポートの fake です。
    private let vehicleResponse = VehicleResponseConfirmationFake()
    /// VIN 読取ポートの fake です。
    private let vinReader = VehicleIdentificationNumberReaderFake()
    /// 自動記録設定の fake です。
    private let automaticRecording = AutomaticRecordingPreferenceFake(isEnabled: true)
    /// 時計の fake です。
    private let clock = AdapterLinkSupervisionClockFake(now: AdapterLinkSupervisionFixtures.referenceDate)
    /// 受け取ったイベントです。
    private var events: [AdapterLinkSupervisionEvent] = []

    /// 責務: 保留中の非同期呼び出しを全て終わらせます。
    override func tearDown() async throws {
        initialization.responses.failAllPending()
        vehicleResponse.responses.failAllPending()
        vinReader.responses.failAllPending()
        clock.sleeps.failAllPending()
        try await super.tearDown()
    }

    /// 検証対象を作り、イベントの記録先へ結び付けます。
    ///
    /// 責務: 全 fake を注入した実行役を返します。
    /// - Returns: 実行役。
    private func makeRunner() -> AdapterLinkSupervisionOperationRunner {
        let runner = AdapterLinkSupervisionOperationRunner(
            initialization: initialization,
            vehicleResponse: vehicleResponse,
            vinReader: vinReader,
            automaticRecordingPreference: automaticRecording,
            clock: clock
        )
        runner.eventDidOccur = { [weak self] event in self?.events.append(event) }
        return runner
    }

    /// 再確認の待機が失敗(取り消し以外も含む)したら、イベントを出しません。
    ///
    /// 責務: 待機の throw が「待機が明けた」に変換されないことを確認します。
    func testSleepFailureEmitsNoEvent() async throws {
        let runner = makeRunner()
        runner.scheduleVehicleConfirmation(after: .seconds(30))
        try await BLEBoundedWaiter.waitUntil("待機の開始") { clock.sleeps.pendingCount == 1 }

        clock.sleeps.resumeOldest(with: .failure(VehicleRecordingTestError.vehicleLoadFailed))
        try await BLEBoundedWaiter.settle()

        XCTAssertEqual(events, [])
        XCTAssertEqual(clock.requestedDurations, [.seconds(30)])
    }

    /// 待機が明けたら「待機が明けた」を1回出します。
    ///
    /// 責務: 待機の成功の変換を、失敗の場合との対として確認します。
    func testSleepSuccessEmitsIntervalElapsed() async throws {
        let runner = makeRunner()
        runner.scheduleVehicleConfirmation(after: .seconds(30))
        try await BLEBoundedWaiter.waitUntil("待機の開始") { clock.sleeps.pendingCount == 1 }

        clock.sleeps.resumeOldest(with: .success(()))
        try await BLEBoundedWaiter.waitUntil("イベント") { !events.isEmpty }

        XCTAssertEqual(events, [.vehicleConfirmationIntervalElapsed])
    }

    /// 取り消さずに次の操作を始めたら、前の操作の結果は捨て、新しい操作の結果だけを出します。
    ///
    /// 責務: 置き換えられた車両確認の結果が、後から届いても出ないことを確認します。
    func testNewOperationSupersedesPreviousWithoutCancel() async throws {
        let runner = makeRunner()
        runner.confirmVehicle(timeout: .standard)
        try await BLEBoundedWaiter.waitUntil("確認の開始") { vehicleResponse.responses.pendingCount == 1 }
        runner.readVIN()
        try await BLEBoundedWaiter.waitUntil("VIN読取の開始") { vinReader.responses.pendingCount == 1 }

        vehicleResponse.responses.resumeOldest(with: .success(.responding))
        try await BLEBoundedWaiter.settle()
        XCTAssertEqual(events, [])
        vinReader.responses.resumeOldest(with: .success(AdapterLinkSupervisionFixtures.vin))
        try await BLEBoundedWaiter.waitUntil("VIN読取のイベント") { !events.isEmpty }

        XCTAssertEqual(events, [.vinReadCompleted(vin: AdapterLinkSupervisionFixtures.vin, isAutomaticRecordingEnabled: true)])
    }

    /// 取り消した後に始めた操作の結果は出し、取り消した操作の結果は出しません。
    ///
    /// 責務: 取り消しで世代が進んだ後も、新しい世代の操作が働くことを確認します。
    func testOperationAfterCancelStillEmits() async throws {
        let runner = makeRunner()
        runner.initializeAdapter()
        try await BLEBoundedWaiter.waitUntil("初期化の開始") { initialization.responses.pendingCount == 1 }
        runner.cancel()
        runner.confirmVehicle(timeout: .adapterMaximum)
        try await BLEBoundedWaiter.waitUntil("確認の開始") { vehicleResponse.responses.pendingCount == 1 }

        initialization.responses.resumeOldest(with: .success(AdapterLinkSupervisionFixtures.evidence))
        vehicleResponse.responses.resumeOldest(with: .success(.noResponse))
        try await BLEBoundedWaiter.waitUntil("確認のイベント") { !events.isEmpty }
        try await BLEBoundedWaiter.settle()

        XCTAssertEqual(events, [.vehicleConfirmationCompleted(.noResponse)])
        XCTAssertEqual(vehicleResponse.timeouts, [.adapterMaximum])
    }

    /// 取り消した後は、保留中だった操作の結果を出しません。
    ///
    /// 責務: 取り消しの後に届いた VIN 読取の失敗が「VIN読取失敗」として出ないことを確認します。
    func testCancelledOperationEmitsNothing() async throws {
        let runner = makeRunner()
        runner.readVIN()
        try await BLEBoundedWaiter.waitUntil("VIN読取の開始") { vinReader.responses.pendingCount == 1 }

        runner.cancel()
        vinReader.responses.resumeOldest(with: .failure(VehicleRecordingTestError.vehicleLoadFailed))
        try await BLEBoundedWaiter.settle()

        XCTAssertEqual(events, [])
    }

    /// 始まる前に取り消された確認・初期化は、アダプターへ何も送りません。
    ///
    /// 責務: 依頼した直後(同じ MainActor の処理の中)に取り消した確認・見張りの確認・初期化で、確認・初期化のポートが呼ばれず、イベントも出ないことを確認します(U3 受け入れ条件 14 に関係する取り消し)。
    func testOperationsCancelledBeforeStartSendNothing() async throws {
        let runner = makeRunner()
        for timeout in [VehicleResponseTimeout.adapterMaximum, .heldWatch] {
            runner.confirmVehicle(timeout: timeout)
            runner.cancel()
        }
        runner.initializeAdapter()
        runner.cancel()
        try await BLEBoundedWaiter.settle()

        XCTAssertEqual(vehicleResponse.timeouts, [])
        XCTAssertEqual(initialization.responses.callCount, 0)
        XCTAssertEqual(events, [])
    }
}
