import XCTest
@testable import ProjectZD8

/// 既定アダプターの状態からアダプターカードの名前・文言キー・記号・主操作を決める規則を検証します。
@MainActor
final class HomeAdapterCardContentTests: XCTestCase {
    private typealias Fixture = HomeScreenTestFixture

    /// 未設定時の見出しキーは未設定の文言です。
    ///
    /// 責務: `notConfiguredTitleKey` を確かめます。
    func testNotConfiguredTitleKey() {
        XCTAssertEqual(HomeAdapterCardContent.notConfiguredTitleKey, "home.adapter.not_configured")
    }

    /// 検出済みは名前・検出済みの文言・チェックとケーブルの記号を持ち、接続先へつなぐ操作になります。
    ///
    /// 責務: detected の全プロパティを確かめます。
    func testDetected() {
        let content = HomeAdapterCardContent(
            availability: .detected(displayName: "My Adapter", endpoint: Fixture.endpoint),
            connectionEndpoint: Fixture.endpoint
        )

        XCTAssertEqual(content.adapterName, "My Adapter")
        XCTAssertEqual(content.statusKey, "home.adapter.detected")
        XCTAssertEqual(content.statusSymbol, "checkmark.circle.fill")
        XCTAssertEqual(content.adapterSymbol, "cable.connector.horizontal")
        XCTAssertTrue(content.isDetected)
        XCTAssertEqual(content.primaryAction, .connect(Fixture.endpoint))
    }

    /// 検出済みの主操作は、検出された接続先ではなく渡された接続先を使います。
    ///
    /// 責務: OS ごとの規則で選ばれた接続先がそのまま操作に入ることを確かめます。
    func testDetectedUsesGivenConnectionEndpoint() {
        let content = HomeAdapterCardContent(
            availability: .detected(displayName: "My Adapter", endpoint: Fixture.endpoint),
            connectionEndpoint: Fixture.otherEndpoint
        )

        XCTAssertEqual(content.primaryAction, .connect(Fixture.otherEndpoint))
    }

    /// 検出済みでも接続先が無ければ、接続先なしの接続操作(無効表示)になります。
    ///
    /// 責務: detected で endpoint が nil の時の主操作を確かめます。
    func testDetectedWithoutEndpointConnectsToNil() {
        let content = HomeAdapterCardContent(
            availability: .detected(displayName: "My Adapter", endpoint: Fixture.endpoint),
            connectionEndpoint: nil
        )

        XCTAssertEqual(content.primaryAction, .connect(nil))
        XCTAssertNotEqual(content.primaryAction, .setupAdapter)
    }

    /// 未検出は名前・未検出の文言・警告とケーブル切断の記号を持ち、アダプター設定の操作になります。
    ///
    /// 責務: notDetected の全プロパティを、接続先が渡されても設定操作になることを含めて確かめます。
    func testNotDetected() {
        let content = HomeAdapterCardContent(
            availability: .notDetected(displayName: "My Adapter"),
            connectionEndpoint: Fixture.endpoint
        )

        XCTAssertEqual(content.adapterName, "My Adapter")
        XCTAssertEqual(content.statusKey, "home.adapter.not_detected")
        XCTAssertEqual(content.statusSymbol, "exclamationmark.circle.fill")
        XCTAssertEqual(content.adapterSymbol, "cable.connector.slash")
        XCTAssertFalse(content.isDetected)
        XCTAssertEqual(content.primaryAction, .setupAdapter)
    }

    /// 未設定は名前が無く、設定が必要な文言・警告とケーブル切断の記号で、アダプター設定の操作になります。
    ///
    /// 責務: notConfigured の全プロパティを確かめます。
    func testNotConfigured() {
        let content = HomeAdapterCardContent(availability: .notConfigured, connectionEndpoint: nil)

        XCTAssertNil(content.adapterName)
        XCTAssertEqual(content.statusKey, "home.adapter.setup_required")
        XCTAssertEqual(content.statusSymbol, "exclamationmark.circle.fill")
        XCTAssertEqual(content.adapterSymbol, "cable.connector.slash")
        XCTAssertFalse(content.isDetected)
        XCTAssertEqual(content.primaryAction, .setupAdapter)
    }
}
