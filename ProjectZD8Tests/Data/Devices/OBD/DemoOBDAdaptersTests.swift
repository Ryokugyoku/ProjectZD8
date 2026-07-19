import XCTest
@testable import ProjectZD8

/// デモOBD識別とPID応答が通常境界と同じ型で返ることを検証します。
@MainActor
final class DemoOBDAdaptersTests: XCTestCase {
    /// 合成VINを持つ登録可能な車両観測を返します。
    ///
    /// 責務: デモ識別結果がVINと車両フィールドを保持することを確認します。
    func testIdentificationReturnsSyntheticVINThroughNormalSnapshot() async throws {
        let snapshot = try await DemoVehicleIdentificationAdapter(
            now: { Date(timeIntervalSince1970: 123) }
        ).identifyVehicle(using: endpoint)

        XCTAssertEqual(snapshot.vin, "TESTZD8CXR0000001")
        XCTAssertEqual(snapshot.fields.first(where: { $0.id == "manufacturer" })?.value, "ProjectZD8 Demo Motors")
        XCTAssertEqual(snapshot.observedAt, Date(timeIntervalSince1970: 123))
    }

    /// 連続読取で車速と回転数が相関して変化します。
    ///
    /// 責務: デモPID境界が要求済み車速と回転数へ更新可能な未加工値を返すことを確認します。
    func testTelemetryReturnsChangingSpeedAndEngineSpeed() async throws {
        let adapter = DemoOBDPIDTelemetryAdapter()
        let speed = OBDPIDRequest(service: 0x01, pid: 0x0D)
        let engineSpeed = OBDPIDRequest(service: 0x01, pid: 0x0C)

        let first = try await adapter.read([speed, engineSpeed], using: endpoint)
        let second = try await adapter.read([speed, engineSpeed], using: endpoint)

        XCTAssertNotEqual(first[speed], second[speed])
        XCTAssertNotEqual(first[engineSpeed], second[engineSpeed])
    }

    /// Bluetoothデモ終端もUSBデモと同じ合成車両へ接続されることを検証します。
    ///
    /// 責務: iOS向けBluetoothデモ終端が通常の識別・PID境界でVINと車速を返すことを確認します。
    func testBluetoothEndpointUsesNormalDemoIdentificationAndTelemetryBoundaries() async throws {
        let bluetoothEndpoint = OBDConnectionEndpoint(adapter: DemoOBDAdapter.bluetoothCandidate)
        let speed = OBDPIDRequest(service: 0x01, pid: 0x0D)

        let snapshot = try await DemoVehicleIdentificationAdapter().identifyVehicle(using: bluetoothEndpoint)
        let readings = try await DemoOBDPIDTelemetryAdapter().read([speed], using: bluetoothEndpoint)

        XCTAssertEqual(snapshot.vin, "TESTZD8CXR0000001")
        XCTAssertNotNil(readings[speed])
    }

    /// テスト用デモ終端です。
    private var endpoint: OBDConnectionEndpoint {
        OBDConnectionEndpoint(adapter: DemoOBDAdapter.candidate)
    }
}
