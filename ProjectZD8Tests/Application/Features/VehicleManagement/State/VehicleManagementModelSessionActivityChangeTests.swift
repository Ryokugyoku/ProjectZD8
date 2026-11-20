import Foundation
import XCTest
@testable import ProjectZD8

/// セッションの活動変化の通知が、Garage の「接続中」表示と接続待ちの段階へ反映されることを検証します。
@MainActor
final class VehicleManagementModelSessionActivityChangeTests: XCTestCase {
    /// サインイン中のアカウントです。
    private static let account = VehicleRecordingCoordinatorHarness.account

    /// 登録済み車両のVINです。
    private static let vin = "JF1ZD8A11P9000001"

    /// 登録済みの車両です。
    private let vehicle = VehicleProfile(vin: vin, name: "BRZ")

    /// 車両の保存先 fake です。
    private let vehicleRepository = AccountScopedVehicleRepositoryFake()

    /// 読込回数を数える接続セッションの保存先 fake です。
    private let sessionRepository = ReadCountingConnectionSessionRepositoryFake()

    /// 責務: 登録済み車両1台を車両の保存先へ用意します。
    override func setUp() async throws {
        try await super.setUp()
        vehicleRepository.vehiclesByAccount[Self.account] = [vehicle]
    }

    /// 対象車両へ関連付いた未終了セッションを保存します。
    ///
    /// 責務: 対象車両の未終了セッションを1件作って保存先へ保存します。
    /// - Returns: 保存したセッションのID。
    @discardableResult
    private func startSession() -> ConnectionSessionID {
        let session = ConnectionSession(
            accountIdentifier: Self.account,
            startedAt: Date(timeIntervalSince1970: 1_000),
            vehicle: ConnectionSessionVehicle(id: vehicle.id, name: vehicle.name, displayIdentifier: Self.vin)
        )
        try? sessionRepository.save(session)
        return session.id
    }

    /// 実物のモデルを fake の保存先へ結び付けて生成します。
    ///
    /// 責務: サインインはせず、車両・セッションの fake だけを結んだモデルを作ります。
    /// - Returns: 生成したモデル。
    private func makeModel() -> VehicleManagementModel {
        VehicleManagementModel(
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
    }

    /// サインインして、車両一覧の読込まで待ったモデルを返します。
    ///
    /// 責務: アカウントを設定し、一覧の読込完了を期限つきで待ちます。
    /// - Returns: 一覧表示中のモデル。
    private func signedInModel() async throws -> VehicleManagementModel {
        let model = makeModel()
        model.send(.accountIdentifierChanged(Self.account))
        try await BLEBoundedWaiter.waitUntil("車両一覧の読込") { model.state.hasLoadedVehicles }
        return model
    }

    /// 対象車両の「接続中」表示が出ているかを返します。
    ///
    /// 責務: 活動の集計に対象車両の接続中が反映されているかを返します。
    /// - Parameter model: 確認するモデル。
    /// - Returns: 接続中と表示される場合は `true`。
    private func isConnected(_ model: VehicleManagementModel) -> Bool {
        model.state.activityByVehicleID[vehicle.id]?.isConnected == true
    }

    /// 接続待ちの段階へ進めたモデルを返します。
    ///
    /// 責務: 識別を通さず、接続待ちと接続対象の車両を状態へ直接設定します。
    /// - Parameter model: 一覧表示中のモデル。
    private func markReadyToConnect(_ model: VehicleManagementModel) {
        model.state.connectionVehicle = vehicle
        model.state.phase = .readyToConnect
    }

    /// セッションが終わった通知を受けると、接続待ちが操作待ちへ戻り、「接続中」が解除されます。
    ///
    /// 責務: `.readyToConnect` で `isSessionActive == false` を受けた時に、集計の再読込と `.idle` への復帰が起きることを確認します。
    func testInactiveWhileReadyToConnectClearsConnectedAndReturnsToIdle() async throws {
        let sessionID = startSession()
        let model = try await signedInModel()
        markReadyToConnect(model)
        XCTAssertTrue(isConnected(model))
        sessionRepository.storage.end(sessionID: sessionID, reason: .userDisconnected)

        model.send(.connectionSessionActivityChanged(isSessionActive: false))

        try await BLEBoundedWaiter.waitUntil("接続中の解除") { !isConnected(model) }
        try await BLEBoundedWaiter.waitUntil("操作待ちへの復帰") { model.state.phase == .idle }
    }

    /// 操作待ちの間にセッションが終わった通知を受けると、「接続中」が解除され、操作待ちのままです。
    ///
    /// 責務: `.idle` でも集計が読み直され、段階が変わらないことを確認します。
    func testInactiveWhileIdleClearsConnectedAndStaysIdle() async throws {
        let sessionID = startSession()
        let model = try await signedInModel()
        XCTAssertTrue(isConnected(model))
        sessionRepository.storage.end(sessionID: sessionID, reason: .userDisconnected)

        model.send(.connectionSessionActivityChanged(isSessionActive: false))

        try await BLEBoundedWaiter.waitUntil("接続中の解除") { !isConnected(model) }
        try await BLEBoundedWaiter.settle()
        XCTAssertEqual(model.state.phase, .idle)
    }

    /// 接続待ちの間にセッションが始まった通知を受けると、「接続中」になり、接続待ちと接続対象を保ちます。
    ///
    /// 責務: `.readyToConnect` で `isSessionActive == true` を受けた時に、集計だけが読み直され段階が変わらないことを確認します。
    func testActiveWhileReadyToConnectShowsConnectedAndKeepsPhase() async throws {
        let model = try await signedInModel()
        markReadyToConnect(model)
        XCTAssertFalse(isConnected(model))
        startSession()

        model.send(.connectionSessionActivityChanged(isSessionActive: true))

        try await BLEBoundedWaiter.waitUntil("接続中の表示") { isConnected(model) }
        try await BLEBoundedWaiter.settle()
        XCTAssertEqual(model.state.phase, .readyToConnect)
        XCTAssertEqual(model.state.connectionVehicle?.id, vehicle.id)
    }

    /// 操作待ちの間にセッションが始まった通知を受けると、「接続中」になり、操作待ちのままです。
    ///
    /// 責務: `.idle` で `isSessionActive == true` を受けた時に、集計が読み直され段階が変わらないことを確認します。
    func testActiveWhileIdleShowsConnectedAndStaysIdle() async throws {
        let model = try await signedInModel()
        XCTAssertFalse(isConnected(model))
        startSession()

        model.send(.connectionSessionActivityChanged(isSessionActive: true))

        try await BLEBoundedWaiter.waitUntil("接続中の表示") { isConnected(model) }
        try await BLEBoundedWaiter.settle()
        XCTAssertEqual(model.state.phase, .idle)
    }

    /// 段階の復帰は通知の値で決まり、集計は保存先の現在の内容をそのまま反映します。
    ///
    /// 責務: 保存先に未終了のセッションが残っていても、`false` の通知で接続待ちが操作待ちへ戻り、集計は接続中のままであることを確認します。
    func testInactiveReturnsToIdleWhileRepositoryStillShowsConnected() async throws {
        startSession()
        let model = try await signedInModel()
        markReadyToConnect(model)

        model.send(.connectionSessionActivityChanged(isSessionActive: false))

        try await BLEBoundedWaiter.waitUntil("操作待ちへの復帰") { model.state.phase == .idle }
        try await BLEBoundedWaiter.settle()
        XCTAssertTrue(isConnected(model))
    }

    /// 登録確認・編集など他の段階では、通知の値にかかわらず、段階と保留中の内容を変えません。
    ///
    /// 責務: 接続待ち・操作待ち以外の各段階と両方の通知値で、段階・登録確認中の観測・編集中の車両が保たれることを確認します。
    func testOtherPhasesKeepPhaseAndPendingContent() async throws {
        let model = try await signedInModel()
        let pending = VehicleIdentificationSnapshot(vin: "PENDING", fields: [], observedAt: Date(timeIntervalSince1970: 0))
        let phases: [VehicleManagementState.Phase] = [.confirmingIdentification, .registering, .editing, .identifying, .failed, .loading]
        for phase in phases {
            for isActive in [true, false] {
                model.state.phase = phase
                model.state.pendingIdentification = pending
                model.state.editingVehicle = vehicle

                model.send(.connectionSessionActivityChanged(isSessionActive: isActive))
                try await BLEBoundedWaiter.settle()

                XCTAssertEqual(model.state.phase, phase, "phase=\(phase) active=\(isActive)")
                XCTAssertEqual(model.state.pendingIdentification, pending, "phase=\(phase) active=\(isActive)")
                XCTAssertEqual(model.state.editingVehicle, vehicle, "phase=\(phase) active=\(isActive)")
            }
        }
    }

    /// アカウントが設定されていなければ、通知を受けても状態を変えず、保存先も読みません。
    ///
    /// 責務: サインイン前の通知で、接続待ちが操作待ちへ戻らず、状態が変わらず、セッションの読込が起きないことを確認します。
    func testWithoutAccountDoesNothing() async throws {
        startSession()
        let model = makeModel()
        markReadyToConnect(model)
        let before = model.state

        model.send(.connectionSessionActivityChanged(isSessionActive: false))
        model.send(.connectionSessionActivityChanged(isSessionActive: true))
        try await BLEBoundedWaiter.settle()

        XCTAssertEqual(model.state, before)
        XCTAssertEqual(sessionRepository.readCount, 0)
    }

    /// サインアウトしてアカウントが無くなった後も、通知を受けて状態を変えず、保存先も読みません。
    ///
    /// 責務: アカウントを `nil` へ戻した後の通知で、状態が初期のままで、読込回数が増えないことを確認します。
    func testAfterSignOutDoesNothing() async throws {
        startSession()
        let model = try await signedInModel()
        model.send(.accountIdentifierChanged(nil))
        let before = model.state
        let readsBefore = sessionRepository.readCount

        model.send(.connectionSessionActivityChanged(isSessionActive: false))
        try await BLEBoundedWaiter.settle()

        XCTAssertEqual(model.state, before)
        XCTAssertEqual(sessionRepository.readCount, readsBefore)
    }
}
