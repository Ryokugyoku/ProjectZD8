import Foundation
import XCTest
@testable import ProjectZD8

/// 接続開始の配線が、登録済み車両と未登録車両それぞれでセッションと取得を正しい車両の状態で始めることを検証します。
@MainActor
final class VehicleConnectionStartWiringTests: XCTestCase {
    /// 各テストのモデル部品です。
    private var telemetry: LiveTelemetryModelFixture?

    /// 動いている取得を止めます。
    ///
    /// 責務: テストごとに応答待ちの要求と取得Taskを片付けます。
    override func tearDown() async throws {
        await telemetry?.tearDown()
        telemetry = nil
        try await super.tearDown()
    }

    /// 未登録車両の接続開始は、車両なしのセッションを作り、未登録として取得を始めます。
    ///
    /// 責務: セッションの車両が無いことと、取得の車両状態が未登録であることを確認します。
    func testStartUnregisteredStartsSessionAndAcquisitionWithoutVehicle() throws {
        let (lifecycle, telemetry) = try makeModels()

        VehicleConnectionStartWiring.startUnregistered(
            endpoint: LiveTelemetryTestDefinitions.endpoint,
            lifecycle: lifecycle,
            liveTelemetry: telemetry.model
        )

        XCTAssertNotNil(lifecycle.activeSession)
        XCTAssertNil(lifecycle.activeSession?.vehicle)
        XCTAssertEqual(telemetry.model.state.vehicle, .unregistered)
        XCTAssertEqual(telemetry.model.state.endpoint, LiveTelemetryTestDefinitions.endpoint)
    }

    /// 登録済み車両の接続開始は、車両付きのセッションを作り、識別がZD8なら型式付きで、そうでなければ型式なしで取得を始めます。
    ///
    /// 責務: セッションの車両と、取得の車両状態(ID・型式コード)を2つの識別で確認します。
    func testStartRegisteredStartsSessionAndAcquisitionWithVehicle() async throws {
        let vehicle = VehicleProfile(vin: "JF1ZD8TEST", name: "BRZ")
        let cases: [(String?, String?)] = [("JF1ZD8TEST000001", ZD8VehicleModelPolicy.modelCode), ("JTEST000000000001", nil)]
        for (vin, expectedCode) in cases {
            let (lifecycle, telemetry) = try makeModels()

            VehicleConnectionStartWiring.startRegistered(
                vehicle,
                endpoint: LiveTelemetryTestDefinitions.endpoint,
                identification: VehicleIdentificationSnapshot(vin: vin, fields: [], observedAt: Date(timeIntervalSince1970: 1)),
                lifecycle: lifecycle,
                liveTelemetry: telemetry.model
            )

            XCTAssertEqual(lifecycle.activeSession?.vehicle?.id, vehicle.id)
            XCTAssertEqual(telemetry.model.state.vehicle, .registered(vehicle.id, vehicleModelCode: expectedCode), "\(String(describing: vin))")
            await telemetry.tearDown()
        }
    }

    /// セッション記録と取得のモデルを作ります。
    ///
    /// 責務: メモリ上のGRDBのライフサイクルモデルと、通信を待たせる取得モデルを返し、取得モデルを後片付けの対象にします。
    /// - Returns: ライフサイクルモデルと取得モデルの部品。
    /// - Throws: DBの準備の失敗。
    private func makeModels() throws -> (ConnectionSessionLifecycleModel, LiveTelemetryModelFixture) {
        let storage = try ConnectionSessionAcquisitionRecorderFixture(storage: .grdb)
        let lifecycle = ConnectionSessionLifecycleModel(repository: storage.sessions, now: { Date(timeIntervalSince1970: 2_000) })
        lifecycle.send(.accountIdentifierChanged("wiring"))
        let telemetry = LiveTelemetryModelFixture(catalog: LiveTelemetryTestDefinitions.standard([0x0C]))
        self.telemetry = telemetry
        return (lifecycle, telemetry)
    }
}
