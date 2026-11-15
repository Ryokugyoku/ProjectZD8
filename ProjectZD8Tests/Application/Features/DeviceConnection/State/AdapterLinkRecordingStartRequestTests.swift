import XCTest
@testable import ProjectZD8

/// `AdapterLinkRecordingStartRequest` の接続対象設定と検知車両からの組み立てを検証します。
@MainActor
final class AdapterLinkRecordingStartRequestTests: XCTestCase {
    /// 共通の fixture です。
    private typealias F = AdapterLinkSupervisionFixtures

    /// 接続終端は接続対象の方式・システム識別子・名称から作り、VINと判定結果は検知車両から引き継ぎます。
    ///
    /// 責務: `init(preference:vehicle:)` の各項目の写し先を確認します。
    func testInitFromPreferenceAndVehicleCopiesEndpointVINAndEvidence() {
        let request = AdapterLinkRecordingStartRequest(preference: F.otherBLEPreference, vehicle: F.detectedVehicle)

        XCTAssertEqual(request.endpoint.transport, .bluetoothLowEnergy)
        XCTAssertEqual(request.endpoint.systemIdentifier, F.otherBLEPreference.systemIdentifier)
        XCTAssertEqual(request.endpoint.displayName, F.otherBLEPreference.displayName)
        XCTAssertEqual(request.vin, F.vin)
        XCTAssertEqual(request.adapterProbeEvidence, F.evidence)
    }

    /// VINが読めなかった検知車両からは、VINなしの要求になります。
    ///
    /// 責務: `nil` のVINがそのまま要求へ渡ることを確認します。
    func testInitWithoutVINKeepsNil() {
        let vehicle = AdapterLinkDetectedVehicle(adapterProbeEvidence: F.otherEvidence, vin: nil)
        let request = AdapterLinkRecordingStartRequest(preference: F.blePreference, vehicle: vehicle)

        XCTAssertNil(request.vin)
        XCTAssertEqual(request.adapterProbeEvidence, F.otherEvidence)
    }
}
