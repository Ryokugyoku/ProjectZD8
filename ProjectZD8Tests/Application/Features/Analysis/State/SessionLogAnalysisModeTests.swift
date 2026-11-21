import Foundation
import XCTest
@testable import ProjectZD8

/// 解析画面の表示モードの識別子とタイトルキーを検証します。
@MainActor
final class SessionLogAnalysisModeTests: XCTestCase {
    /// 既存の3モードが、この順で先頭に並びます。
    ///
    /// 責務: 切り替えUIの並び(走行サマリー、推移、相関)が変わらないことを確認します。
    func testAllCasesStartWithExistingThreeModesInOrder() {
        XCTAssertEqual(Array(SessionLogAnalysisMode.allCases.prefix(3)), [.overview, .trends, .relationships])
    }

    /// 識別子は rawValue と同じです。
    ///
    /// 責務: Picker の識別子が安定した文字列であることを確認します。
    func testIdentifierEqualsRawValue() {
        XCTAssertEqual(SessionLogAnalysisMode.overview.id, "overview")
        XCTAssertEqual(SessionLogAnalysisMode.trends.id, "trends")
        XCTAssertEqual(SessionLogAnalysisMode.relationships.id, "relationships")
        XCTAssertEqual(Set(SessionLogAnalysisMode.allCases.map(\.id)).count, SessionLogAnalysisMode.allCases.count)
    }

    /// 既存モードのタイトルキーは変わりません。
    ///
    /// 責務: 3モードのローカライズキーを確認します。
    func testTitleKeysOfExistingModes() {
        XCTAssertEqual(SessionLogAnalysisMode.overview.titleKey, "analysis.mode.overview")
        XCTAssertEqual(SessionLogAnalysisMode.trends.titleKey, "analysis.mode.trends")
        XCTAssertEqual(SessionLogAnalysisMode.relationships.titleKey, "analysis.mode.relationships")
    }

    /// 既存3モードのタイトルキーが重複せず、文言へ解決できます。
    ///
    /// 責務: キーが String Catalog に存在し(キー自体が返らない)、モード間で重複しないことを確認します。
    func testEveryTitleKeyIsUniqueAndLocalized() {
        let keys = SessionLogAnalysisMode.allCases.prefix(3).map(\.titleKey)

        XCTAssertEqual(Set(keys).count, keys.count)
        for key in keys {
            XCTAssertNotEqual(String(localized: String.LocalizationValue(key)), key)
        }
    }

    /// ルートのモードは識別子とタイトルキーを持ち、最後に並びます。
    ///
    /// 責務: `.route` の id・titleKey・allCases の数と順を確認します。
    func testRouteModeIdentifierTitleKeyAndPosition() {
        XCTAssertEqual(SessionLogAnalysisMode.route.id, "route")
        XCTAssertEqual(SessionLogAnalysisMode.route.titleKey, "analysis.mode.route")
        XCTAssertEqual(SessionLogAnalysisMode.allCases, [.overview, .trends, .relationships, .route])
        XCTAssertEqual(SessionLogAnalysisMode.allCases.last, .route)
    }

    /// ルートのモードのタイトルキーが文言へ解決できます。
    ///
    /// 責務: `analysis.mode.route` がカタログに存在し(キー自体が返らない)、他のモードと重複しないことを確認します。
    func testRouteTitleKeyIsLocalizedAndDistinct() {
        let key = SessionLogAnalysisMode.route.titleKey
        XCTAssertNotEqual(String(localized: String.LocalizationValue(key)), key)
        XCTAssertEqual(SessionLogAnalysisMode.allCases.filter { $0.titleKey == key }.count, 1)
    }
}
