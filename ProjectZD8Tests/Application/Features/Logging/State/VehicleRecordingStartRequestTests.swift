import Foundation
import XCTest
@testable import ProjectZD8

/// `VehicleRecordingStartRequest` の生成(手動接続・常駐リンク)と型式コードの判定を検証します。
@MainActor
final class VehicleRecordingStartRequestTests: XCTestCase {
    /// ZD8 型式に該当するVINです。
    private static let zd8VIN = "JF1ZD8A11P9000001"

    /// ZD8 型式に該当しないVINです。
    private static let otherVIN = "WVWZZZ1KZ6W000002"

    /// 記録に使う接続終端です。
    private static let endpoint = OBDConnectionEndpoint(transport: .bluetoothLowEnergy, systemIdentifier: "id", displayName: "A")

    /// アダプター判定結果です。
    private static let evidence = AcquisitionAdapterProbeEvidence(chipFamily: .stn, monitorProbeOutcome: .framesReceived)

    /// 識別観測を作ります。
    ///
    /// 責務: 指定のVINとOBD識別子を持つ観測を返します。
    /// - Parameters:
    ///   - vin: 観測したVIN。
    ///   - obdIdentifier: 観測したOBD識別子。
    /// - Returns: 識別観測。
    private func snapshot(vin: String?, obdIdentifier: String? = nil) -> VehicleIdentificationSnapshot {
        VehicleIdentificationSnapshot(vin: vin, obdIdentifier: obdIdentifier, fields: [], observedAt: Date(timeIntervalSince1970: 0))
    }

    /// 指定値をそのまま保持します。
    ///
    /// 責務: 初期化引数の5項目が同じ値で読めることを確認します。
    func testInitializerKeepsAllValues() {
        let vehicle = VehicleProfile(vin: Self.zd8VIN, name: "BRZ")
        let request = VehicleRecordingStartRequest(
            endpoint: Self.endpoint, vehicle: vehicle, observedVIN: "V", vehicleModelCode: "M", adapterProbeEvidence: Self.evidence
        )
        XCTAssertEqual(request.endpoint, Self.endpoint)
        XCTAssertEqual(request.vehicle, vehicle)
        XCTAssertEqual(request.observedVIN, "V")
        XCTAssertEqual(request.vehicleModelCode, "M")
        XCTAssertEqual(request.adapterProbeEvidence, Self.evidence)
    }

    /// 手動接続の要求は車両あり・観測VINなし・判定結果なしで、識別観測から型式コードを決めます。
    ///
    /// 責務: VIN・OBD識別子のどちらかが ZD8 なら型式コードが付き、どちらも該当しなければ付かないことを確認します。
    func testManualConnectionRequest() {
        let vehicle = VehicleProfile(vin: Self.otherVIN, name: "BRZ")
        let byVIN = VehicleRecordingStartRequest.manualConnection(
            vehicle: vehicle, endpoint: Self.endpoint, identification: snapshot(vin: Self.zd8VIN)
        )
        XCTAssertEqual(byVIN.vehicle, vehicle)
        XCTAssertEqual(byVIN.endpoint, Self.endpoint)
        XCTAssertNil(byVIN.observedVIN)
        XCTAssertNil(byVIN.adapterProbeEvidence)
        XCTAssertEqual(byVIN.vehicleModelCode, ZD8VehicleModelPolicy.modelCode)

        let byIdentifier = VehicleRecordingStartRequest.manualConnection(
            vehicle: vehicle, endpoint: Self.endpoint, identification: snapshot(vin: nil, obdIdentifier: "ZD8-ECU")
        )
        XCTAssertEqual(byIdentifier.vehicleModelCode, ZD8VehicleModelPolicy.modelCode)

        let neither = VehicleRecordingStartRequest.manualConnection(
            vehicle: vehicle, endpoint: Self.endpoint, identification: snapshot(vin: Self.otherVIN, obdIdentifier: "OTHER")
        )
        XCTAssertNil(neither.vehicleModelCode)
    }

    /// 常駐リンクの要求は終端・VIN・判定結果を要求から、車両を引数から取り、一致車両から型式コードを決めます。
    ///
    /// 責務: ZD8 車両に一致した場合と、ZD8 でない車両に一致した場合の型式コードを確認します。
    func testResidentLinkRequestWithVehicle() {
        let source = AdapterLinkRecordingStartRequest(endpoint: Self.endpoint, vin: Self.zd8VIN, adapterProbeEvidence: Self.evidence)
        let zd8 = VehicleProfile(vin: Self.zd8VIN, name: "BRZ")
        let request = VehicleRecordingStartRequest.residentLink(source, vehicle: zd8)
        XCTAssertEqual(request.endpoint, Self.endpoint)
        XCTAssertEqual(request.vehicle, zd8)
        XCTAssertEqual(request.observedVIN, Self.zd8VIN)
        XCTAssertEqual(request.adapterProbeEvidence, Self.evidence)
        XCTAssertEqual(request.vehicleModelCode, ZD8VehicleModelPolicy.modelCode)

        let otherSource = AdapterLinkRecordingStartRequest(endpoint: Self.endpoint, vin: Self.otherVIN, adapterProbeEvidence: Self.evidence)
        let other = VehicleProfile(vin: Self.otherVIN, name: "Golf")
        XCTAssertNil(VehicleRecordingStartRequest.residentLink(otherSource, vehicle: other).vehicleModelCode)
    }

    /// 常駐リンクの要求で車両なし・VINなしなら、車両・観測VIN・型式コードはすべて nil です。
    ///
    /// 責務: VIN を読めなかった記録の要求を確認します。
    func testResidentLinkRequestWithoutVehicleOrVIN() {
        let source = AdapterLinkRecordingStartRequest(endpoint: Self.endpoint, vin: nil, adapterProbeEvidence: Self.evidence)
        let request = VehicleRecordingStartRequest.residentLink(source, vehicle: nil)
        XCTAssertNil(request.vehicle)
        XCTAssertNil(request.observedVIN)
        XCTAssertNil(request.vehicleModelCode)
        XCTAssertEqual(request.adapterProbeEvidence, Self.evidence)
    }

    /// 手動接続で未登録だった場合の要求は、車両なし・型式コードなし・判定結果なしで、識別で読めたVINを観測VINとして持ちます。
    ///
    /// 責務: ZD8 形式のVINやOBD識別子を読めても、未登録なら型式コードを付けないことを確認します。
    func testManualUnregisteredConnectionRequest() {
        let request = VehicleRecordingStartRequest.manualUnregisteredConnection(
            endpoint: Self.endpoint, identification: snapshot(vin: Self.zd8VIN, obdIdentifier: "ZD8-ECU")
        )

        XCTAssertEqual(request.endpoint, Self.endpoint)
        XCTAssertNil(request.vehicle)
        XCTAssertEqual(request.observedVIN, Self.zd8VIN)
        XCTAssertNil(request.vehicleModelCode)
        XCTAssertNil(request.adapterProbeEvidence)
    }

    /// 手動接続で未登録かつVINを読めなかった場合、観測VINは `nil` です。
    ///
    /// 責務: 読めなかったVINを空文字などで補完しないことを確認します。
    func testManualUnregisteredConnectionWithoutVIN() {
        let request = VehicleRecordingStartRequest.manualUnregisteredConnection(
            endpoint: Self.endpoint, identification: snapshot(vin: nil, obdIdentifier: "ZD8-ECU")
        )

        XCTAssertNil(request.observedVIN)
        XCTAssertNil(request.vehicleModelCode)
    }

    /// 常駐リンクで読んだVINが ZD8 形式でも、一致した登録済み車両が無ければ型式コードは付きません。
    ///
    /// 責務: 型式コードを読んだVINからではなく、一致した登録済み車両からだけ決めることを確認します。
    func testResidentLinkUnregisteredZD8VINHasNoModelCode() {
        let source = AdapterLinkRecordingStartRequest(endpoint: Self.endpoint, vin: Self.zd8VIN, adapterProbeEvidence: Self.evidence)

        let request = VehicleRecordingStartRequest.residentLink(source, vehicle: nil)

        XCTAssertNil(request.vehicle)
        XCTAssertEqual(request.observedVIN, Self.zd8VIN)
        XCTAssertNil(request.vehicleModelCode)
        XCTAssertEqual(request.adapterProbeEvidence, Self.evidence)
    }

    /// 常駐リンクで一致した登録済み車両は、VINが ZD8 でなくてもOBD識別子が ZD8 なら型式コードが付き、
    /// 読んだVINが ZD8 形式でも一致車両の識別子がどちらも該当しなければ付きません。
    ///
    /// 責務: 一致車両のVIN・OBD識別子の両方を判定に使い、読んだVINを使わないことを確認します。
    func testResidentLinkModelCodeComesFromMatchedVehicleIdentifiers() {
        let source = AdapterLinkRecordingStartRequest(endpoint: Self.endpoint, vin: Self.zd8VIN, adapterProbeEvidence: Self.evidence)
        let byIdentifier = VehicleProfile(vin: Self.otherVIN, obdIdentifier: "ZD8-ECU", name: "BRZ")
        let neither = VehicleProfile(vin: Self.otherVIN, obdIdentifier: "OTHER", name: "Golf")

        XCTAssertEqual(VehicleRecordingStartRequest.residentLink(source, vehicle: byIdentifier).vehicleModelCode, "ZD8")
        XCTAssertNil(VehicleRecordingStartRequest.residentLink(source, vehicle: neither).vehicleModelCode)
    }

    /// 型式コードは識別子のどれか1件でも ZD8 なら付き、空配列・nil・空文字・非該当だけなら付きません。
    ///
    /// 責務: `vehicleModelCode(identifiers:)` の境界を確認します。
    func testVehicleModelCodeBoundaries() {
        XCTAssertNil(VehicleRecordingStartRequest.vehicleModelCode(identifiers: []))
        XCTAssertNil(VehicleRecordingStartRequest.vehicleModelCode(identifiers: [nil, nil]))
        XCTAssertNil(VehicleRecordingStartRequest.vehicleModelCode(identifiers: ["", "  "]))
        XCTAssertNil(VehicleRecordingStartRequest.vehicleModelCode(identifiers: [Self.otherVIN]))
        XCTAssertEqual(VehicleRecordingStartRequest.vehicleModelCode(identifiers: [nil, Self.otherVIN, Self.zd8VIN]), "ZD8")
        XCTAssertEqual(VehicleRecordingStartRequest.vehicleModelCode(identifiers: [Self.zd8VIN.lowercased()]), "ZD8")
    }
}
