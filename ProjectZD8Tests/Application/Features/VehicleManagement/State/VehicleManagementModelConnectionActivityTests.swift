import Foundation
import XCTest
@testable import ProjectZD8

/// Garage の「接続中」表示が、セッションの終了後の再読込で解除されることを検証します。
@MainActor
final class VehicleManagementModelConnectionActivityTests: XCTestCase {
    /// サインイン中のアカウントです。
    private static let account = VehicleRecordingCoordinatorHarness.account

    /// 登録済み車両のVINです。
    private static let vin = "JF1ZD8A11P9000001"

    /// 手動接続の終端です。
    private static let endpoint = VehicleRecordingCoordinatorHarness.endpoint

    /// 登録済みの車両です。
    private let vehicle = VehicleProfile(vin: vin, name: "BRZ")

    /// 車両の保存先 fake です。
    private let vehicleRepository = AccountScopedVehicleRepositoryFake()

    /// 接続セッションの保存先 fake です。
    private let sessionRepository = MutableConnectionSessionRepositoryFake()

    /// 責務: 登録済み車両1台を車両の保存先へ用意します。
    override func setUp() async throws {
        try await super.setUp()
        vehicleRepository.vehiclesByAccount[Self.account] = [vehicle]
    }

    /// 対象車両へ関連付いた未終了セッションを保存します。
    ///
    /// 責務: 接続の確定時に保存されるセッションを、実際の配線と同じく未終了で作ります。
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

    /// 識別成功時にセッションを保存するモデルを作り、サインインして一覧の読込まで待ちます。
    ///
    /// 責務: 実物のモデルを fake の識別ポートと保存先へ結び付け、`connectionVehicleDidResolve` でセッションを保存します。
    /// - Parameter sessionID: 識別成功時に保存したセッションのIDを受け取る入れ物。
    /// - Returns: 一覧表示中のモデル。
    private func signedInModel(sessionID: SessionIDBox) async throws -> VehicleManagementModel {
        let snapshot = VehicleIdentificationSnapshot(vin: Self.vin, fields: [], observedAt: Date(timeIntervalSince1970: 0))
        let model = VehicleManagementModel(
            state: VehicleManagementState(),
            repository: vehicleRepository,
            identifyForConnection: IdentifyVehicleForConnectionUseCase(
                identification: ScriptedVehicleIdentificationPort(result: .success(snapshot))
            ),
            photoImporter: ObservedVINRegistrationPhotoImportStub(),
            loadVehicleActivitySummaries: LoadVehicleActivitySummariesUseCase(repository: sessionRepository),
            connectionVehicleDidResolve: { [weak self] _, _, _ in sessionID.value = self?.startSession() }
        )
        model.send(.accountIdentifierChanged(Self.account))
        try await BLEBoundedWaiter.waitUntil("車両一覧の読込") { model.state.hasLoadedVehicles }
        return model
    }

    /// 識別を成功させ、接続待ちの状態と「接続中」表示まで待ちます。
    ///
    /// 責務: 手動接続の識別から `.readyToConnect` と対象車両の接続中表示までを再現します。
    /// - Parameter model: 一覧表示中のモデル。
    private func connectManually(_ model: VehicleManagementModel) async throws {
        model.send(.identifyRequested(Self.endpoint))
        try await BLEBoundedWaiter.waitUntil("接続待ち") { model.state.phase == .readyToConnect }
        try await BLEBoundedWaiter.waitUntil("接続中の表示") { [vehicle] in
            model.state.activityByVehicleID[vehicle.id]?.isConnected == true
        }
    }

    /// 手動接続で `.readyToConnect` になった後にセッションが終了し、再読込を要求すると「接続中」が解除されます。
    ///
    /// 責務: `phase` が `.idle` でなくても活動の集計が読み直され、`.readyToConnect` と識別結果が保たれることを確認します。
    func testRefreshAfterSessionEndedClearsConnectedWhileReadyToConnect() async throws {
        let sessionID = SessionIDBox()
        let model = try await signedInModel(sessionID: sessionID)
        try await connectManually(model)
        let endedID = try XCTUnwrap(sessionID.value)
        sessionRepository.end(sessionID: endedID, reason: .userDisconnected)

        model.send(.refreshRequested)

        try await BLEBoundedWaiter.waitUntil("接続中の解除") { [vehicle] in
            model.state.activityByVehicleID[vehicle.id]?.isConnected == false
        }
        XCTAssertEqual(model.state.phase, .readyToConnect)
        XCTAssertEqual(model.state.connectionVehicle?.id, vehicle.id)
        XCTAssertEqual(model.state.vehicles.map(\.id), [vehicle.id])
    }

    /// セッションが続いている間の再読込は、`.readyToConnect` も識別結果も「接続中」も変えません。
    ///
    /// 責務: `.readyToConnect` 中の再読込が識別結果を失わせず、未終了のセッションを接続中のまま保つことを確認します。
    func testRefreshWhileSessionActiveKeepsReadyToConnectAndConnected() async throws {
        let model = try await signedInModel(sessionID: SessionIDBox())
        try await connectManually(model)

        model.send(.refreshRequested)
        try await BLEBoundedWaiter.settle()

        XCTAssertEqual(model.state.phase, .readyToConnect)
        XCTAssertEqual(model.state.connectionVehicle?.id, vehicle.id)
        XCTAssertEqual(model.state.vehicles.map(\.id), [vehicle.id])
        XCTAssertEqual(model.state.activityByVehicleID[vehicle.id]?.isConnected, true)
    }

    /// `.idle` の間(自動記録を想定)にセッションが終了し、再読込を要求すると「接続中」が解除されます。
    ///
    /// 責務: 自動記録で始まったセッションの終了が、再読込で表示へ反映されることを確認します。
    func testRefreshAfterAutomaticSessionEndedClearsConnectedWhileIdle() async throws {
        let model = try await signedInModel(sessionID: SessionIDBox())
        let endedID = startSession()
        model.send(.refreshRequested)
        try await BLEBoundedWaiter.waitUntil("接続中の表示") { [vehicle] in
            model.state.activityByVehicleID[vehicle.id]?.isConnected == true
        }
        XCTAssertEqual(model.state.phase, .idle)
        sessionRepository.end(sessionID: endedID, reason: .userDisconnected)

        model.send(.refreshRequested)

        try await BLEBoundedWaiter.waitUntil("接続中の解除") { [vehicle] in
            model.state.activityByVehicleID[vehicle.id]?.isConnected == false
        }
    }
}

/// 識別成功時に保存したセッションのIDを、モデルの通知先から読み出すための入れ物です。
@MainActor
private final class SessionIDBox {
    /// 最後に保存したセッションのIDです。
    var value: ConnectionSessionID?
}
