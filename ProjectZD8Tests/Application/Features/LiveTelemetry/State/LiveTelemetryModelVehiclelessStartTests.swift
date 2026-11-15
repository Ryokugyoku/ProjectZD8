import Foundation
import XCTest
@testable import ProjectZD8

/// `LiveTelemetryModel` の車両なし開始、失敗状態、再試行を検証します。
@MainActor
final class LiveTelemetryModelVehiclelessStartTests: XCTestCase {
    /// 固定値の短縮名です。
    private typealias Fixtures = AdapterPIDDiscoveryFixtures

    /// 車両なしの開始要求で、アダプターが対応と答えカタログにあるPIDの取得が始まります。
    ///
    /// 責務: 車両なしでも取得が `.loaded` まで進み、車両別対応PIDの保存に触れないことを確認します。
    func testVehiclelessStartPollsDiscoveredPIDsWithoutTouchingCapabilityRepository() async throws {
        let telemetry = Fixtures.adapter()
        let repository = VehiclePIDCapabilityRepositorySpy()
        let model = makeModel(telemetry: telemetry, repository: repository)

        model.send(.startRequested(request(vehicleID: nil)))
        try await BLEBoundedWaiter.waitUntil("車両なし開始の取得開始") { model.state.phase == .loaded }

        XCTAssertEqual(Set(model.state.samples.map(\.request)), [Fixtures.standard(0x05), Fixtures.standard(0x0C)])
        XCTAssertNil(model.state.vehicleID)
        XCTAssertEqual(repository.totalCallCount, 0)
        try await stop(model)
    }

    /// 車両なしで2回開始すると、アダプターへ2回問い合わせます。
    ///
    /// 責務: 車両なしの対応PIDが開始ごとに探索され、保存も再利用もされないことを確認します。
    func testVehiclelessStartTwiceQueriesAdapterTwice() async throws {
        let telemetry = Fixtures.adapter()
        let repository = VehiclePIDCapabilityRepositorySpy()
        let model = makeModel(telemetry: telemetry, repository: repository)

        model.send(.startRequested(request(vehicleID: nil)))
        try await BLEBoundedWaiter.waitUntil("1回目の取得開始") { model.state.phase == .loaded }
        model.send(.startRequested(request(vehicleID: nil)))
        try await BLEBoundedWaiter.waitUntil("2回目の探索") { telemetry.discoveryCount == 2 && model.state.phase == .loaded }

        XCTAssertEqual(telemetry.discoveryCount, 2)
        XCTAssertEqual(repository.totalCallCount, 0)
        try await stop(model)
    }

    /// 探索手段が注入されていない状態で車両なし開始をすると `unavailable` の失敗状態になります。
    ///
    /// 責務: 探索手段の欠落が成功や空データにならず、取得失敗として終わることを確認します。
    func testVehiclelessStartWithoutDiscoveryFailsAsUnavailable() async throws {
        let telemetry = Fixtures.adapter()
        var endReasons: [ConnectionSessionEndReason] = []
        let model = makeModel(telemetry: telemetry, repository: VehiclePIDCapabilityRepositorySpy(), injectsDiscovery: false) {
            endReasons.append($0)
        }

        model.send(.startRequested(request(vehicleID: nil)))
        try await BLEBoundedWaiter.waitUntil("失敗状態") { model.state.phase == .failed }

        XCTAssertEqual(model.state.failureKey, "telemetry.error.unavailable")
        XCTAssertTrue(model.state.samples.isEmpty)
        XCTAssertEqual(endReasons, [.acquisitionFailed])
        XCTAssertTrue(telemetry.bitmapQueries.isEmpty)
    }

    /// 車両なし開始でアダプターへの探索が失敗すると失敗状態になります。
    ///
    /// 責務: 探索失敗が空データの成功へ潰されず、取得失敗として終わることを確認します。
    func testVehiclelessStartFailsWhenAdapterDiscoveryFails() async throws {
        var endReasons: [ConnectionSessionEndReason] = []
        let model = makeModel(
            telemetry: Fixtures.adapter(bitmapFailure: AdapterPIDDiscoveryTestError.adapterFailed),
            repository: VehiclePIDCapabilityRepositorySpy()
        ) { endReasons.append($0) }

        model.send(.startRequested(request(vehicleID: nil)))
        try await BLEBoundedWaiter.waitUntil("失敗状態") { model.state.phase == .failed }

        XCTAssertEqual(model.state.failureKey, "telemetry.error.read_failed")
        XCTAssertTrue(model.state.samples.isEmpty)
        XCTAssertEqual(endReasons, [.acquisitionFailed])
    }

    /// 対応PIDが0件のとき、車両あり・なしで同じ失敗状態になります。
    ///
    /// 責務: 同じアダプター応答に対し、車両なしの扱いが既存の車両ありの挙動と一致することを確認します。
    func testZeroSupportedPIDsEndsInSameStateWithAndWithoutVehicle() async throws {
        let withVehicle = makeModel(telemetry: Fixtures.silentAdapter, repository: VehiclePIDCapabilityRepositorySpy())
        let withoutVehicle = makeModel(telemetry: Fixtures.silentAdapter, repository: VehiclePIDCapabilityRepositorySpy())

        withVehicle.send(.startRequested(request(vehicleID: Fixtures.vehicleID)))
        withoutVehicle.send(.startRequested(request(vehicleID: nil)))
        try await BLEBoundedWaiter.waitUntil("両方の終了") {
            withVehicle.state.phase != .reading && withoutVehicle.state.phase != .reading
        }

        XCTAssertEqual(withVehicle.state.phase, .failed)
        XCTAssertEqual(withVehicle.state.failureKey, "telemetry.error.pid_catalog_unavailable")
        XCTAssertEqual(withoutVehicle.state.phase, withVehicle.state.phase)
        XCTAssertEqual(withoutVehicle.state.failureKey, withVehicle.state.failureKey)
    }

    /// 直前が車両なしの開始なら、再試行も車両なしで再開します。
    ///
    /// 責務: 再試行が車両なしの開始要求をそのまま使い、アダプターへ再度問い合わせることを確認します。
    func testRetryAfterVehiclelessStartRestartsWithoutVehicle() async throws {
        let telemetry = Fixtures.adapter()
        let repository = VehiclePIDCapabilityRepositorySpy()
        let model = makeModel(telemetry: telemetry, repository: repository)
        let original = request(vehicleID: nil)

        model.send(.startRequested(original))
        try await BLEBoundedWaiter.waitUntil("初回の取得開始") { model.state.phase == .loaded }
        model.send(.retryRequested)
        try await BLEBoundedWaiter.waitUntil("再試行の探索") { telemetry.discoveryCount == 2 && model.state.phase == .loaded }

        XCTAssertEqual(model.state.startRequest, original)
        XCTAssertEqual(repository.totalCallCount, 0)
        try await stop(model)
    }

    /// 直前が車両ありの開始なら、再試行も同じ車両で再開します。
    ///
    /// 責務: 再試行が同じ車両IDで保存済み対応PIDを読み直し、アダプター探索へ切り替わらないことを確認します。
    func testRetryAfterVehicleStartRestartsWithSameVehicle() async throws {
        let telemetry = Fixtures.adapter()
        let repository = VehiclePIDCapabilityRepositorySpy(
            stored: [Fixtures.vehicleID: Fixtures.storedCapabilities([(Fixtures.standard(0x0C), true)])]
        )
        let model = makeModel(telemetry: telemetry, repository: repository)
        let original = request(vehicleID: Fixtures.vehicleID)

        model.send(.startRequested(original))
        try await BLEBoundedWaiter.waitUntil("初回の取得開始") { model.state.phase == .loaded }
        model.send(.retryRequested)
        try await BLEBoundedWaiter.waitUntil("再試行の読込") { repository.readVehicleIDs.count == 2 && model.state.phase == .loaded }

        XCTAssertEqual(repository.readVehicleIDs, [Fixtures.vehicleID, Fixtures.vehicleID])
        XCTAssertEqual(telemetry.discoveryCount, 0)
        XCTAssertEqual(model.state.startRequest, original)
        try await stop(model)
    }

    /// 一度も開始していなければ再試行は何もしません。
    ///
    /// 責務: 開始要求が無い再試行が状態・アダプター・保存先のいずれも変えないことを確認します。
    func testRetryWithoutPriorStartDoesNothing() async throws {
        let telemetry = Fixtures.adapter()
        let repository = VehiclePIDCapabilityRepositorySpy()
        let model = makeModel(telemetry: telemetry, repository: repository)

        model.send(.retryRequested)
        XCTAssertEqual(model.state.phase, .idle)
        try await BLEBoundedWaiter.settle()

        XCTAssertEqual(model.state.phase, .idle)
        XCTAssertNil(model.state.startRequest)
        XCTAssertTrue(telemetry.bitmapQueries.isEmpty)
        XCTAssertTrue(telemetry.dataReads.isEmpty)
        XCTAssertEqual(repository.totalCallCount, 0)
    }

    // MARK: - Helpers

    /// 検証対象のモデルを組み立てます。
    ///
    /// 責務: 同じアダプターとカタログを共有する定義読込・車両別対応PID・保存なし探索をモデルへ注入します。
    /// - Parameters:
    ///   - telemetry: アダプターのフェイク。
    ///   - repository: 車両別対応PIDの保存先。
    ///   - injectsDiscovery: `false` の場合は保存なし探索を注入しません。
    ///   - sessionDidEnd: 取得終了理由の通知先。
    /// - Returns: 取得証跡なしの検証対象モデル。
    private func makeModel(
        telemetry: AdapterPIDTelemetryFake,
        repository: VehiclePIDCapabilityRepositorySpy,
        injectsDiscovery: Bool = true,
        sessionDidEnd: @escaping @MainActor (ConnectionSessionEndReason) -> Void = { _ in }
    ) -> LiveTelemetryModel {
        let catalog = Fixtures.catalog
        return LiveTelemetryModel(
            readMajorPIDs: ReadMajorOBDPIDsUseCase(definitionRepository: catalog, telemetry: telemetry),
            loadVehicleCapabilities: LoadVehiclePIDCapabilitiesUseCase(
                repository: repository,
                telemetry: telemetry,
                definitionRepository: catalog
            ),
            discoverSupportedPIDs: injectsDiscovery
                ? DiscoverSupportedOBDPIDsUseCase(telemetry: telemetry, definitionRepository: catalog)
                : nil,
            sessionDidEnd: sessionDidEnd
        )
    }

    /// テスト用の開始要求を返します。
    ///
    /// 責務: 車両IDだけを変えた型式なしの開始要求を作ります。
    /// - Parameter vehicleID: 登録車両ID。車両なしは `nil`。
    /// - Returns: 固定終端の開始要求。
    private func request(vehicleID: VehicleID?) -> LiveTelemetryStartRequest {
        LiveTelemetryStartRequest(endpoint: Fixtures.endpoint, vehicleID: vehicleID, vehicleModelCode: nil)
    }

    /// 取得を停止し、待機状態へ戻るまで待ちます。
    ///
    /// 責務: 後続テストへ取得loopを残さないよう上限付きで停止完了を待ちます。
    /// - Parameter model: 停止するモデル。
    private func stop(_ model: LiveTelemetryModel) async throws {
        model.send(.stopRequested)
        try await BLEBoundedWaiter.waitUntil("停止完了") { model.state.phase == .idle }
    }
}
