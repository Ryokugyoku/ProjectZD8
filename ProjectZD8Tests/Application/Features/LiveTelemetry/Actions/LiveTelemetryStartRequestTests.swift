import Foundation
import XCTest
@testable import ProjectZD8

/// 取得開始要求 `LiveTelemetryStartRequest` の既定値と同値判定を検証します。
final class LiveTelemetryStartRequestTests: XCTestCase {
    /// テスト用OBD終端です。
    private let endpoint = OBDConnectionEndpoint(transport: .serial, systemIdentifier: "/dev/request", displayName: "Request")
    /// テスト用登録車両IDです。
    private let vehicleID = VehicleID(rawValue: UUID(uuidString: "30000000-0000-0000-0000-000000000003")!)
    /// ATMA判定ありのアダプター判定結果です。
    private let probe = AcquisitionAdapterProbeEvidence(chipFamily: .stn, monitorProbeOutcome: .framesReceived)

    /// アダプター判定結果を省略すると `nil` になります。
    ///
    /// 責務: 既定引数がアダプター判定なしを表すことを確認します。
    func testAdapterProbeEvidenceDefaultsToNil() {
        let request = LiveTelemetryStartRequest(endpoint: endpoint, vehicleID: vehicleID, vehicleModelCode: "ZD8")

        XCTAssertNil(request.adapterProbeEvidence)
    }

    /// 渡した終端・車両・型式・判定結果をそのまま保持します。
    ///
    /// 責務: 初期化引数が各プロパティへ欠落なく入ることを確認します。
    func testKeepsEveryGivenValue() {
        let request = LiveTelemetryStartRequest(endpoint: endpoint, vehicleID: vehicleID, vehicleModelCode: "ZD8", adapterProbeEvidence: probe)

        XCTAssertEqual(request.endpoint, endpoint)
        XCTAssertEqual(request.vehicleID, vehicleID)
        XCTAssertEqual(request.vehicleModelCode, "ZD8")
        XCTAssertEqual(request.adapterProbeEvidence, probe)
    }

    /// 車両IDと型式に `nil` を渡せます。
    ///
    /// 責務: 車両なしの開始要求が表現できることを確認します。
    func testAcceptsVehiclelessRequest() {
        let request = LiveTelemetryStartRequest(endpoint: endpoint, vehicleID: nil, vehicleModelCode: nil)

        XCTAssertNil(request.vehicleID)
        XCTAssertNil(request.vehicleModelCode)
        XCTAssertEqual(request.endpoint, endpoint)
    }

    /// 車両の有無が違えば別の要求として扱います。
    ///
    /// 責務: 再試行が車両ありと車両なしを取り違えないための同値判定を確認します。
    func testRequestsDifferingOnlyInVehicleAreNotEqual() {
        let withVehicle = LiveTelemetryStartRequest(endpoint: endpoint, vehicleID: vehicleID, vehicleModelCode: nil)
        let withoutVehicle = LiveTelemetryStartRequest(endpoint: endpoint, vehicleID: nil, vehicleModelCode: nil)

        XCTAssertNotEqual(withVehicle, withoutVehicle)
    }

    /// アダプター判定結果が違えば別の要求として扱います。
    ///
    /// 責務: 判定結果のあり・なし、ATMA結果の違いを同値判定が区別することを確認します。
    func testRequestsDifferingOnlyInProbeEvidenceAreNotEqual() {
        let chipOnly = AcquisitionAdapterProbeEvidence(chipFamily: .stn, monitorProbeOutcome: nil)
        let none = LiveTelemetryStartRequest(endpoint: endpoint, vehicleID: nil, vehicleModelCode: nil)
        let withChipOnly = LiveTelemetryStartRequest(endpoint: endpoint, vehicleID: nil, vehicleModelCode: nil, adapterProbeEvidence: chipOnly)
        let withATMA = LiveTelemetryStartRequest(endpoint: endpoint, vehicleID: nil, vehicleModelCode: nil, adapterProbeEvidence: probe)

        XCTAssertNotEqual(none, withChipOnly)
        XCTAssertNotEqual(withChipOnly, withATMA)
    }

    /// 同じ値で作った要求は等しくなります。
    ///
    /// 責務: 全項目一致の要求が同値と判定されることを確認します。
    func testRequestsWithSameValuesAreEqual() {
        let first = LiveTelemetryStartRequest(endpoint: endpoint, vehicleID: nil, vehicleModelCode: "ZD8", adapterProbeEvidence: probe)
        let second = LiveTelemetryStartRequest(endpoint: endpoint, vehicleID: nil, vehicleModelCode: "ZD8", adapterProbeEvidence: probe)

        XCTAssertEqual(first, second)
    }
}
