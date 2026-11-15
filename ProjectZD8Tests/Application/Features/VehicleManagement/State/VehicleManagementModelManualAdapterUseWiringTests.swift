import Foundation
import XCTest
@testable import ProjectZD8

/// `VehicleManagementModel` の識別通知と車両確定を、App(`IOSApplicationRoot`)と同じ形で `VehicleRecordingCoordinator` へ結び付けた時、
/// 1回の手動使用につき「使い始めた」「使い終えた」が1回ずつ常駐リンク監視へ伝わることを検証します。
/// 未登録車両の識別では、識別の時点で車両なしの記録が始まり、登録後は新しい記録を始めず同じセッションへ車両を関連付けます。
///
/// iOS 専用の App 配線そのものは macOS のテストでコンパイルされないため、ここでは同じ結び付けをテスト内で組み立てます。
@MainActor
final class VehicleManagementModelManualAdapterUseWiringTests: XCTestCase {
    /// 登録済み車両のVINです。
    private static let vin = "JF1ZD8A11P9000001"

    /// 記録の調停役の組み立てです。
    private var harness: VehicleRecordingCoordinatorHarness!

    /// 調停役へ結び付けたモデルを作り、サインインして一覧の読込まで待ちます。
    ///
    /// 責務: 識別開始・識別終了・車両確定を調停役の入力へ結び付けます。
    /// - Parameters:
    ///   - result: 識別ポートが返す結果。
    ///   - registered: サインイン中アカウントの登録済み車両。
    /// - Returns: 一覧表示中のモデル。
    private func wiredModel(
        result: Result<VehicleIdentificationSnapshot, any Error>, registered: [VehicleProfile] = []
    ) async throws -> VehicleManagementModel {
        harness = VehicleRecordingCoordinatorHarness()
        harness.signIn()
        harness.register(registered)
        let coordinator: VehicleRecordingCoordinator = harness.coordinator
        let model = VehicleManagementModel(
            state: VehicleManagementState(),
            repository: harness.vehicleRepository,
            identifyForConnection: IdentifyVehicleForConnectionUseCase(identification: ScriptedVehicleIdentificationPort(result: result)),
            photoImporter: ObservedVINRegistrationPhotoImportStub(),
            connectionVehicleDidResolve: { vehicle, endpoint, identification in
                coordinator.startManualRecording(.manualConnection(vehicle: vehicle, endpoint: endpoint, identification: identification))
            },
            unregisteredConnectionDidStart: { endpoint, identification in
                coordinator.startManualRecording(.manualUnregisteredConnection(endpoint: endpoint, identification: identification))
            },
            unregisteredConnectionVehicleDidRegister: { [lifecycle = harness.lifecycle] in lifecycle.send(.unregisteredVehicleRegistered($0)) },
            vehicleDidRegister: { [lifecycle = harness.lifecycle] vehicle, _ in lifecycle.send(.observedVINVehicleRegistered(vehicle)) },
            connectionIdentificationWillBegin: { coordinator.manualConnectionIdentificationWillBegin() },
            connectionIdentificationDidEnd: { coordinator.manualConnectionIdentificationDidEnd() }
        )
        model.send(.accountIdentifierChanged(VehicleRecordingCoordinatorHarness.account))
        try await BLEBoundedWaiter.waitUntil("車両一覧の読込") { model.state.hasLoadedVehicles }
        return model
    }

    /// 識別を要求し、識別が終わる(準備完了か登録確認か失敗)まで上限付きで待ちます。
    ///
    /// 責務: 識別要求を送り、識別中でなくなるまで待ちます。
    /// - Parameter model: 一覧表示中のモデル。
    private func identify(_ model: VehicleManagementModel) async throws {
        model.send(.identifyRequested(VehicleRecordingCoordinatorHarness.endpoint))
        try await BLEBoundedWaiter.waitUntil("識別の終了") {
            [.readyToConnect, .confirmingIdentification, .failed].contains(model.state.phase)
        }
        try await BLEBoundedWaiter.settle()
    }

    /// 識別から記録へ続いた場合、「使い始めた」は1回で、記録が終わった時に「使い終えた」が1回伝わります。
    ///
    /// 責務: 識別終了の時点では終了が出ず、テレメトリ終了で1回出ることを確認します。
    func testIdentificationToRecordingIsOneManualUse() async throws {
        let snapshot = VehicleIdentificationSnapshot(vin: Self.vin, fields: [], observedAt: Date(timeIntervalSince1970: 0))
        let model = try await wiredModel(result: .success(snapshot), registered: [VehicleProfile(vin: Self.vin, name: "BRZ")])

        try await identify(model)
        XCTAssertEqual(model.state.phase, .readyToConnect)
        XCTAssertEqual(harness.manualUseBeganCount, 1)
        XCTAssertEqual(harness.manualUseEndedCount, 0)
        XCTAssertEqual(harness.telemetryRequests.count, 1)

        harness.telemetryDidEnd(reason: .userDisconnected)
        XCTAssertEqual(harness.manualUseBeganCount, 1)
        XCTAssertEqual(harness.manualUseEndedCount, 1)
    }

    /// 識別が失敗した場合、「使い始めた」と「使い終えた」が1回ずつ伝わり、記録は始まりません。
    ///
    /// 責務: 失敗の識別で開始・終了が1回ずつであることを確認します。
    func testFailedIdentificationIsOneManualUse() async throws {
        let model = try await wiredModel(result: .failure(VehicleIdentificationError.connectionFailed))

        try await identify(model)

        XCTAssertEqual(model.state.phase, .failed)
        XCTAssertEqual(harness.manualUseBeganCount, 1)
        XCTAssertEqual(harness.manualUseEndedCount, 1)
        XCTAssertTrue(harness.telemetryRequests.isEmpty)
    }

    /// 未登録で登録確認へ進んだ場合、識別の時点で車両なしの記録が始まって「使い始めた」は1回、識別が終わっても「使い終えた」は出ません。
    /// 登録画面で保存しても新しい記録は始まらず、同じセッションに車両が入り、記録の終了で「使い終えた」が1回伝わります。
    ///
    /// 責務: 未登録の識別から登録・記録終了までが1回の手動使用として数えられ、記録が1件だけであることを確認します。
    func testUnregisteredIdentificationRecordsWithoutVehicleAndSaveBindsSameSession() async throws {
        let snapshot = VehicleIdentificationSnapshot(vin: Self.vin, fields: [], observedAt: Date(timeIntervalSince1970: 0))
        let model = try await wiredModel(result: .success(snapshot))

        try await identify(model)
        XCTAssertEqual(model.state.phase, .confirmingIdentification)
        XCTAssertEqual(harness.manualUseBeganCount, 1)
        XCTAssertEqual(harness.manualUseEndedCount, 0)
        XCTAssertEqual(harness.telemetryRequests.map(\.vehicle), [nil])
        XCTAssertEqual(harness.telemetryRequests.first?.observedVIN, Self.vin)
        let session = try XCTUnwrap(harness.lifecycle.activeSession)

        model.send(.identificationConfirmed)
        var vehicle = try XCTUnwrap(model.state.editingVehicle)
        vehicle.name = "BRZ"
        model.send(.vehicleSaved(vehicle))
        try await BLEBoundedWaiter.waitUntil("登録の保存") { model.state.phase == .idle }
        try await BLEBoundedWaiter.settle()

        XCTAssertEqual(harness.telemetryRequests.count, 1)
        XCTAssertEqual(harness.lifecycle.activeSession?.id, session.id)
        XCTAssertEqual(harness.lifecycle.activeSession?.vehicle?.id, vehicle.id)
        XCTAssertEqual(harness.manualUseBeganCount, 1)
        XCTAssertEqual(harness.manualUseEndedCount, 0)
        harness.telemetryDidEnd(reason: .userDisconnected)
        XCTAssertEqual(harness.manualUseEndedCount, 1)
    }
}
