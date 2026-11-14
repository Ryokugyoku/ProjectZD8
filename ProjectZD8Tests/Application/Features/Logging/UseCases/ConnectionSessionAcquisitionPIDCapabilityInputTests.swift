import XCTest
@testable import ProjectZD8

/// 取得manifestへ渡すPIDのcapability証跡のうち、未登録車両用の値を検証します。
final class ConnectionSessionAcquisitionPIDCapabilityInputTests: XCTestCase {
    /// 未登録車両の証跡は、ECUの応答に基づく対応と、常に有効な収集選択を持ちます。
    ///
    /// 責務: 要求・対応・収集選択の値を確認します。
    func testUnregisteredVehicleEvidenceValues() {
        let request = OBDPIDRequest(service: 0x01, pid: 0x0C)

        let input = ConnectionSessionAcquisitionPIDCapabilityInput.unregisteredVehicleSupported(request)

        XCTAssertEqual(input.request, request)
        XCTAssertEqual(input.support, .supported)
        XCTAssertTrue(input.isCollectionEnabled)
    }
}
