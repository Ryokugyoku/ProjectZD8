import Foundation
import XCTest
@testable import ProjectZD8

/// `StartVehicleRecordingSessionUseCase` が「セッション開始 → 車両確定 → 観測VIN」の順で接続セッションを準備することを検証します。
@MainActor
final class StartVehicleRecordingSessionUseCaseTests: XCTestCase {
    /// 代表VINです。
    private static let vin = "JF1ZD8A11P9000001"

    /// 記録に使う接続終端です。
    private static let endpoint = OBDConnectionEndpoint(transport: .bluetoothLowEnergy, systemIdentifier: "id", displayName: "A")

    /// セッションの保存先 spy です。
    private var repository: SavingConnectionSessionRepositorySpy!

    /// 指定アカウントで有効化した接続セッションモデルを作ります。
    ///
    /// 責務: 保存先 spy を結び付け、アカウントを設定したモデルを返します。
    /// - Parameter account: アカウント識別子。`nil` なら未サインイン。
    /// - Returns: 未開始のモデル。
    private func makeLifecycle(account: String? = "account") -> ConnectionSessionLifecycleModel {
        repository = SavingConnectionSessionRepositorySpy()
        let lifecycle = ConnectionSessionLifecycleModel(repository: repository)
        lifecycle.send(.accountIdentifierChanged(account))
        return lifecycle
    }

    /// 記録開始要求を作ります。
    ///
    /// 責務: 指定の車両と観測VINを持つ要求を返します。
    /// - Parameters:
    ///   - vehicle: 確定する車両。
    ///   - observedVIN: 観測VIN。
    /// - Returns: 記録開始要求。
    private func request(vehicle: VehicleProfile?, observedVIN: String?) -> VehicleRecordingStartRequest {
        VehicleRecordingStartRequest(
            endpoint: Self.endpoint, vehicle: vehicle, observedVIN: observedVIN, vehicleModelCode: nil, adapterProbeEvidence: nil
        )
    }

    /// 車両ありの要求ではセッションを開始してから車両を確定し、true を返します。
    ///
    /// 責務: 保存順が「開始 → 車両確定」で、進行中セッションに車両が入ることを確認します。
    func testVehicleRequestStartsSessionThenBindsVehicle() throws {
        let lifecycle = makeLifecycle()
        let vehicle = VehicleProfile(vin: Self.vin, name: "BRZ")

        let started = StartVehicleRecordingSessionUseCase(lifecycle: lifecycle).execute(request(vehicle: vehicle, observedVIN: nil))

        XCTAssertTrue(started)
        XCTAssertEqual(repository.saved.count, 2)
        XCTAssertNil(repository.saved.first?.vehicle)
        XCTAssertEqual(repository.saved.last?.vehicle, ConnectionSessionVehicle(profile: vehicle))
        XCTAssertEqual(lifecycle.activeSession?.vehicle, ConnectionSessionVehicle(profile: vehicle))
    }

    /// 車両なし・観測VINありの要求ではセッションを開始してから観測VINを記録します。
    ///
    /// 責務: 保存順が「開始 → 観測VIN」で、車両は未確定のままであることを確認します。
    func testObservedVINRequestStartsSessionThenRecordsVIN() {
        let lifecycle = makeLifecycle()

        let started = StartVehicleRecordingSessionUseCase(lifecycle: lifecycle).execute(request(vehicle: nil, observedVIN: Self.vin))

        XCTAssertTrue(started)
        XCTAssertEqual(repository.saved.map(\.observedVIN), [nil, Self.vin])
        XCTAssertNil(lifecycle.activeSession?.vehicle)
        XCTAssertEqual(lifecycle.activeSession?.observedVIN, Self.vin)
    }

    /// 車両も観測VINもない要求では、セッションの開始だけを行います。
    ///
    /// 責務: 保存が1回だけで、車両と観測VINが空のままであることを確認します。
    func testEmptyRequestOnlyStartsSession() {
        let lifecycle = makeLifecycle()

        let started = StartVehicleRecordingSessionUseCase(lifecycle: lifecycle).execute(request(vehicle: nil, observedVIN: nil))

        XCTAssertTrue(started)
        XCTAssertEqual(repository.saved.count, 1)
        XCTAssertNil(lifecycle.activeSession?.vehicle)
        XCTAssertNil(lifecycle.activeSession?.observedVIN)
    }

    /// 未サインインではセッションを開始できず false を返し、何も保存しません。
    ///
    /// 責務: アカウント未確定時に車両確定・観測VINへ進まないことを確認します。
    func testSignedOutReturnsFalseWithoutSaving() {
        let lifecycle = makeLifecycle(account: nil)
        let vehicle = VehicleProfile(vin: Self.vin, name: "BRZ")

        let started = StartVehicleRecordingSessionUseCase(lifecycle: lifecycle).execute(request(vehicle: vehicle, observedVIN: Self.vin))

        XCTAssertFalse(started)
        XCTAssertTrue(repository.saved.isEmpty)
        XCTAssertNil(lifecycle.activeSession)
    }

    /// 保存に失敗したら false を返します。
    ///
    /// 責務: セッション開始の保存失敗を成功扱いにしないことを確認します。
    func testSaveFailureReturnsFalse() {
        let lifecycle = makeLifecycle()
        repository.failsSave = true

        let started = StartVehicleRecordingSessionUseCase(lifecycle: lifecycle).execute(request(vehicle: nil, observedVIN: Self.vin))

        XCTAssertFalse(started)
        XCTAssertNil(lifecycle.activeSession)
    }

    /// 進行中セッションの有無を返します。
    ///
    /// 責務: 開始前は false、開始後は true、終了後は false になることを確認します。
    func testHasActiveSessionReflectsLifecycle() {
        let lifecycle = makeLifecycle()
        let useCase = StartVehicleRecordingSessionUseCase(lifecycle: lifecycle)
        XCTAssertFalse(useCase.hasActiveSession)

        _ = useCase.execute(request(vehicle: nil, observedVIN: nil))
        XCTAssertTrue(useCase.hasActiveSession)

        lifecycle.send(.endRequested(.userDisconnected))
        XCTAssertFalse(useCase.hasActiveSession)
    }
}
