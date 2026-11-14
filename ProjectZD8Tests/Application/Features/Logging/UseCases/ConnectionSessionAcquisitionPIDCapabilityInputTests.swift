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

    /// 未登録車両の証跡は、登録済み車両の対応済み・収集有効の証跡と区別できます(仕様C)。
    ///
    /// 責務: 同じPIDについて、未登録車両用の値が登録済み車両の値と異なることを確認します。
    func testUnregisteredVehicleEvidenceDiffersFromRegistered() {
        let request = OBDPIDRequest(service: 0x01, pid: 0x0C)
        let registered = ConnectionSessionAcquisitionPIDCapabilityInput(request: request, support: .supported, isCollectionEnabled: true)

        XCTAssertNotEqual(ConnectionSessionAcquisitionPIDCapabilityInput.unregisteredVehicleSupported(request), registered)
    }
}
