import Foundation
import XCTest
@testable import ProjectZD8

/// `LiveTelemetryState` の開始要求から導く終端・車両・型式を検証します。
final class LiveTelemetryStateTests: XCTestCase {
    /// テスト用OBD終端です。
    private let endpoint = OBDConnectionEndpoint(transport: .serial, systemIdentifier: "/dev/state", displayName: "State")
    /// テスト用登録車両IDです。
    private let vehicleID = VehicleID(rawValue: UUID(uuidString: "40000000-0000-0000-0000-000000000004")!)

    /// 開始要求が無ければ終端・車両・型式はすべて `nil` です。
    ///
    /// 責務: 一度も開始していない状態で導出値が空であることを確認します。
    func testDerivedValuesAreNilWithoutStartRequest() {
        let state = LiveTelemetryState()

        XCTAssertNil(state.startRequest)
        XCTAssertNil(state.endpoint)
        XCTAssertNil(state.vehicleID)
        XCTAssertNil(state.vehicleModelCode)
    }

    /// 車両ありの開始要求から終端・車両・型式を導きます。
    ///
    /// 責務: 3つの計算プロパティが開始要求の値を返すことを確認します。
    func testDerivesValuesFromVehicleRequest() {
        var state = LiveTelemetryState()
        state.startRequest = LiveTelemetryStartRequest(endpoint: endpoint, vehicleID: vehicleID, vehicleModelCode: "ZD8")

        XCTAssertEqual(state.endpoint, endpoint)
        XCTAssertEqual(state.vehicleID, vehicleID)
        XCTAssertEqual(state.vehicleModelCode, "ZD8")
    }

    /// 車両なしの開始要求では終端だけを持ち、車両と型式は `nil` です。
    ///
    /// 責務: 車両なしで記録中の状態が終端を失わないことを確認します。
    func testVehiclelessRequestKeepsEndpointWithoutVehicle() {
        var state = LiveTelemetryState()
        state.startRequest = LiveTelemetryStartRequest(endpoint: endpoint, vehicleID: nil, vehicleModelCode: nil)

        XCTAssertEqual(state.endpoint, endpoint)
        XCTAssertNil(state.vehicleID)
        XCTAssertNil(state.vehicleModelCode)
    }

    /// 開始要求を差し替えると導出値も追従します。
    ///
    /// 責務: 導出値が古い開始要求の値を残さないことを確認します。
    func testDerivedValuesFollowReplacedRequest() {
        var state = LiveTelemetryState()
        state.startRequest = LiveTelemetryStartRequest(endpoint: endpoint, vehicleID: vehicleID, vehicleModelCode: "ZD8")
        state.startRequest = LiveTelemetryStartRequest(endpoint: endpoint, vehicleID: nil, vehicleModelCode: nil)

        XCTAssertNil(state.vehicleID)
        XCTAssertNil(state.vehicleModelCode)
    }
}
