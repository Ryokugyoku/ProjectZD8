import XCTest
@testable import ProjectZD8

/// 本番の取得証拠契約versionを検証します。
final class ProductionConnectionSessionAcquisitionConfigurationTests: XCTestCase {
    /// polling policy契約versionは応答駆動の周回番号を表す2です。
    ///
    /// 責務: 本番構成のpolling policy versionが2であることを確認します。
    func testPollingPolicyVersionIsTwo() {
        XCTAssertEqual(ProductionConnectionSessionAcquisitionConfiguration.phase4G.pollingPolicyVersion, 2)
    }
}
