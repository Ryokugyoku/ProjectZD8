import Foundation
import XCTest
@testable import ProjectZD8

/// 接続セッションの開始・終了が、実物の接続ライフサイクルから実物の車両管理モデル(Garage の「接続中」表示)へ伝わることを検証します。
///
/// 両モデルは同じセッション保存先の fake を共有し、ライフサイクルが保存・終了した内容を Garage 側が読む実際の配線を再現します。
@MainActor
final class ConnectionSessionActivityRelayTests: XCTestCase {
    /// サインイン中のアカウントです。
    private static let account = VehicleRecordingCoordinatorHarness.account

    /// 登録済み車両のVINです。
    private static let vin = "JF1ZD8A11P9000001"

    /// 登録済みの車両です。
    private let vehicle = VehicleProfile(vin: vin, name: "BRZ")

    /// 車両の保存先 fake です。
    private let vehicleRepository = AccountScopedVehicleRepositoryFake()

    /// ライフサイクルと Garage が共有する、読込回数つきのセッション保存先 fake です。
    private let sessionRepository = ReadCountingConnectionSessionRepositoryFake()

    /// 実物の接続ライフサイクルのモデルです。
    private var lifecycle = ConnectionSessionLifecycleModel(repository: ReadCountingConnectionSessionRepositoryFake())

    /// 責務: 車両を登録し、共有の保存先へ結んだライフサイクルをサインイン済みで用意します。
    override func setUp() async throws {
        try await super.setUp()
        vehicleRepository.vehiclesByAccount[Self.account] = [vehicle]
        lifecycle = ConnectionSessionLifecycleModel(repository: sessionRepository)
        lifecycle.send(.accountIdentifierChanged(Self.account))
    }

    /// 共有の保存先から活動を集計する実物の車両管理モデルを、サインインして一覧の読込まで待って返します。
    ///
    /// 責務: 車両・セッションの fake だけを結んだモデルを作り、一覧の読込完了を期限つきで待ちます。
    /// - Returns: 一覧表示中のモデル。
    private func signedInGarage() async throws -> VehicleManagementModel {
        let model = VehicleManagementModel(
            state: VehicleManagementState(),
            repository: vehicleRepository,
            identifyForConnection: IdentifyVehicleForConnectionUseCase(
                identification: ScriptedVehicleIdentificationPort(
                    result: .success(VehicleIdentificationSnapshot(vin: Self.vin, fields: [], observedAt: Date(timeIntervalSince1970: 0)))
                )
            ),
            photoImporter: ObservedVINRegistrationPhotoImportStub(),
            loadVehicleActivitySummaries: LoadVehicleActivitySummariesUseCase(repository: sessionRepository)
        )
        model.send(.accountIdentifierChanged(Self.account))
        try await BLEBoundedWaiter.waitUntil("車両一覧の読込") { model.state.hasLoadedVehicles }
        try await BLEBoundedWaiter.settle()
        return model
    }

    /// 対象車両に紐づいたセッションを開始します。
    ///
    /// 責務: 開始と車両の確定を同じ実行の中で続けて送り、Garage 側の再読込より前に車両つきで保存された状態にします。
    private func startVehicleSession() {
        lifecycle.send(.startRequested)
        lifecycle.send(.vehicleResolved(vehicle))
    }

    /// 対象車両の「接続中」表示が出ているかを返します。
    ///
    /// 責務: 活動の集計に対象車両の接続中が反映されているかを返します。
    /// - Parameter model: 確認する Garage のモデル。
    /// - Returns: 接続中と表示される場合は `true`。
    private func isConnected(_ model: VehicleManagementModel) -> Bool {
        model.state.activityByVehicleID[vehicle.id]?.isConnected == true
    }

    /// 開始したセッションが Garage の「接続中」へ伝わります。
    ///
    /// 責務: `start` の後にセッションを車両つきで開始すると、対象車両が接続中になることを確認します。
    func testSessionStartShowsConnectedInGarage() async throws {
        let garage = try await signedInGarage()
        ConnectionSessionActivityRelay.start(lifecycle: lifecycle, vehicleManagement: garage)
        XCTAssertFalse(isConnected(garage))

        startVehicleSession()

        try await BLEBoundedWaiter.waitUntil("接続中の表示") { isConnected(garage) }
    }

    /// 終了したセッションが Garage の「接続中」の解除へ伝わります(今回の不具合の結合再現)。
    ///
    /// 責務: 接続中の表示後にセッションを終了すると、対象車両の接続中が解除されることを確認します。
    func testSessionEndClearsConnectedInGarage() async throws {
        let garage = try await signedInGarage()
        ConnectionSessionActivityRelay.start(lifecycle: lifecycle, vehicleManagement: garage)
        startVehicleSession()
        try await BLEBoundedWaiter.waitUntil("接続中の表示") { isConnected(garage) }

        lifecycle.send(.endRequested(.userDisconnected))

        try await BLEBoundedWaiter.waitUntil("接続中の解除") { !isConnected(garage) }
        XCTAssertNil(lifecycle.activeSession)
    }

    /// 接続待ちの間にセッションが終了すると、Garage が操作待ちへ戻ります。
    ///
    /// 責務: `.readyToConnect` の Garage でセッションが終了した時に、段階が `.idle` へ戻ることを確認します。
    func testSessionEndWhileReadyToConnectReturnsGarageToIdle() async throws {
        let garage = try await signedInGarage()
        ConnectionSessionActivityRelay.start(lifecycle: lifecycle, vehicleManagement: garage)
        startVehicleSession()
        try await BLEBoundedWaiter.waitUntil("接続中の表示") { isConnected(garage) }
        garage.state.connectionVehicle = vehicle
        garage.state.phase = .readyToConnect

        lifecycle.send(.endRequested(.userDisconnected))

        try await BLEBoundedWaiter.waitUntil("操作待ちへの復帰") { garage.state.phase == .idle }
    }

    /// アカウント変更でセッションが無くなった場合も、Garage が活動を読み直します。
    ///
    /// 責務: ライフサイクルだけのアカウントを `nil` にして `activeSession` が消えた時に、Garage のセッション読込が増えることを確認します。
    func testAccountChangeClearingActiveSessionRefreshesGarage() async throws {
        let garage = try await signedInGarage()
        ConnectionSessionActivityRelay.start(lifecycle: lifecycle, vehicleManagement: garage)
        startVehicleSession()
        try await BLEBoundedWaiter.waitUntil("接続中の表示") { isConnected(garage) }
        try await BLEBoundedWaiter.settle()
        let readsBefore = sessionRepository.readCount

        lifecycle.send(.accountIdentifierChanged(nil))

        XCTAssertNil(lifecycle.activeSession)
        try await BLEBoundedWaiter.waitUntil("活動の読み直し") { sessionRepository.readCount > readsBefore }
    }

    /// `start` を呼んだだけでは、何も送りません。
    ///
    /// 責務: 開いているセッションがある状態で `start` を呼んでも、Garage の状態とセッションの読込回数が変わらないことを確認します。
    func testStartAloneSendsNothing() async throws {
        startVehicleSession()
        let garage = try await signedInGarage()
        let stateBefore = garage.state
        let readsBefore = sessionRepository.readCount

        ConnectionSessionActivityRelay.start(lifecycle: lifecycle, vehicleManagement: garage)
        try await BLEBoundedWaiter.settle()

        XCTAssertEqual(garage.state, stateBefore)
        XCTAssertEqual(sessionRepository.readCount, readsBefore)
    }

    /// セッションの識別子が変わらない更新では、何も送りません。
    ///
    /// 責務: 開いているセッションへ走行距離を保存しても、Garage のセッション読込回数が増えないことを確認します。
    func testSameSessionUpdateSendsNothing() async throws {
        let garage = try await signedInGarage()
        ConnectionSessionActivityRelay.start(lifecycle: lifecycle, vehicleManagement: garage)
        startVehicleSession()
        try await BLEBoundedWaiter.waitUntil("接続中の表示") { isConnected(garage) }
        try await BLEBoundedWaiter.settle()
        let readsBefore = sessionRepository.readCount
        let sessionID = lifecycle.activeSession?.id

        lifecycle.send(.distanceObserved(.init(source: .odometer, kilometers: 100)))
        lifecycle.send(.distanceObserved(.init(source: .odometer, kilometers: 101.5)))
        try await BLEBoundedWaiter.settle()

        XCTAssertEqual(lifecycle.activeSession?.endingOdometerKilometers, 101.5, "更新が実際にセッションへ入っている")
        XCTAssertEqual(lifecycle.activeSession?.id, sessionID)
        XCTAssertEqual(sessionRepository.readCount, readsBefore)
    }

    /// `start` を呼ばなければ、セッションの開始・終了は Garage へ伝わりません(対照)。
    ///
    /// 責務: 配線なしでセッションを開始・終了しても、Garage の接続中表示と読込回数が変わらないことを確認します。
    func testWithoutStartNothingReachesGarage() async throws {
        let garage = try await signedInGarage()
        let readsBefore = sessionRepository.readCount

        startVehicleSession()
        try await BLEBoundedWaiter.settle()
        XCTAssertNotNil(lifecycle.activeSession)
        lifecycle.send(.endRequested(.userDisconnected))
        try await BLEBoundedWaiter.settle()

        XCTAssertNil(lifecycle.activeSession)
        XCTAssertFalse(isConnected(garage))
        XCTAssertEqual(sessionRepository.readCount, readsBefore)
    }

    /// 指定した車両の「接続中」表示が出ているかを返します。
    ///
    /// 責務: 活動の集計に指定車両の接続中が反映されているかを返します。
    /// - Parameters:
    ///   - model: 確認する Garage のモデル。
    ///   - vehicleID: 確認する車両のID。
    /// - Returns: 接続中と表示される場合は `true`。
    private func isConnected(_ model: VehicleManagementModel, vehicleID: VehicleID) -> Bool {
        model.state.activityByVehicleID[vehicleID]?.isConnected == true
    }

    /// 車両なしで始まったセッションへ後から車両が確定しても、Garage の「接続中」になります。
    ///
    /// 責務: 車両なしのセッションを Garage が読み終えた後に車両を確定すると、対象車両が接続中になることを確認します。
    func testVehicleResolvedAfterSessionStartShowsConnectedInGarage() async throws {
        let garage = try await signedInGarage()
        ConnectionSessionActivityRelay.start(lifecycle: lifecycle, vehicleManagement: garage)
        let readsBefore = sessionRepository.readCount
        lifecycle.send(.startRequested)
        try await BLEBoundedWaiter.waitUntil("車両なしのセッションの読込") { sessionRepository.readCount > readsBefore }
        try await BLEBoundedWaiter.settle()
        XCTAssertFalse(isConnected(garage))

        lifecycle.send(.vehicleResolved(vehicle))

        try await BLEBoundedWaiter.waitUntil("接続中の表示") { isConnected(garage) }
    }

    /// 同じセッションのまま車両が別の車両に替わると、「接続中」も付け替わります。
    ///
    /// 責務: 同じセッションへ別の車両を確定すると、前の車両の接続中が解除され、新しい車両が接続中になることを確認します。
    func testVehicleChangeInSameSessionMovesConnectedInGarage() async throws {
        let other = VehicleProfile(vin: "JF1ZD8A11P9000002", name: "GR86")
        vehicleRepository.vehiclesByAccount[Self.account] = [vehicle, other]
        let garage = try await signedInGarage()
        ConnectionSessionActivityRelay.start(lifecycle: lifecycle, vehicleManagement: garage)
        startVehicleSession()
        try await BLEBoundedWaiter.waitUntil("最初の車両の接続中") { isConnected(garage, vehicleID: vehicle.id) }
        let sessionID = lifecycle.activeSession?.id

        lifecycle.send(.vehicleResolved(other))

        XCTAssertEqual(lifecycle.activeSession?.id, sessionID, "同じセッションのまま車両だけが替わる")
        try await BLEBoundedWaiter.waitUntil("新しい車両の接続中") { isConnected(garage, vehicleID: other.id) }
        try await BLEBoundedWaiter.waitUntil("前の車両の接続中の解除") { !isConnected(garage, vehicleID: vehicle.id) }
    }
}
