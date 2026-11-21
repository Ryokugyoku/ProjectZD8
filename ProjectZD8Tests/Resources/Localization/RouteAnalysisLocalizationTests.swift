import Foundation
import XCTest
@testable import ProjectZD8

/// 走行ルートの色分け(`analysis.route.*` と `analysis.mode.route`)の文言キーが、`Localizable.xcstrings` で ja / en / es に訳されていることを検証します。
@MainActor
final class RouteAnalysisLocalizationTests: XCTestCase {
    /// 設計書 §6 の、色分けの指標以外の `analysis.route.*` のキーです(逆方向の `map.select_hint` は作らない判断なので含めません)。
    private static let designKeys = [
        "analysis.route.title", "analysis.route.subtitle", "analysis.route.color_source", "analysis.route.metric.unavailable",
        "analysis.route.legend.title", "analysis.route.legend.below", "analysis.route.legend.range",
        "analysis.route.legend.at_least", "analysis.route.legend.no_value", "analysis.route.notice.no_matching_values",
        "analysis.route.notice.no_color_source", "analysis.route.cursor.no_position", "analysis.route.chart.metric_title",
        "analysis.route.elevation.title", "analysis.route.elevation.subtitle", "analysis.route.elevation.unavailable"
    ]

    /// 責務: 色分けの指標の文言キーを `RouteAnalysisColorMetric.allCases` から作ります。
    private func metricKeys() -> [String] {
        RouteAnalysisColorMetric.allCases.map(\.titleKey)
    }

    /// 色分けの指標4種の文言キーが、重複なくカタログにあります。
    ///
    /// 責務: `RouteAnalysisColorMetric.allCases` の `titleKey` を確認します。
    func testMetricTitleKeysAreTranslated() throws {
        let keys = metricKeys()
        let catalog = try LocalizableCatalogChecker()
        catalog.assertDistinct(keys, expectedCount: 4)
        catalog.assertAll(keys)
        XCTAssertTrue(keys.allSatisfy { $0.hasPrefix("analysis.route.metric.") })
    }

    /// 既にある表示モードの文言キーと、ルートの表示モードのキーが、カタログにあります。
    ///
    /// 責務: `SessionLogAnalysisMode.allCases` の `titleKey` と `analysis.mode.route` を確認します。
    func testModeTitleKeysAreTranslated() throws {
        let keys = SessionLogAnalysisMode.allCases.map(\.titleKey)
        XCTAssertTrue(keys.contains("analysis.mode.route"), "ルートの表示モードのキーが allCases に無い")
        let catalog = try LocalizableCatalogChecker()
        catalog.assertDistinct(keys, expectedCount: SessionLogAnalysisMode.allCases.count)
        catalog.assertAll(keys)
    }

    /// 設計書の `analysis.route.*` のキーが、カタログにあります。
    ///
    /// 責務: タイトル・凡例・注記・標高などの16キーを確認します。
    func testDesignKeysAreTranslated() throws {
        let catalog = try LocalizableCatalogChecker()
        catalog.assertDistinct(Self.designKeys, expectedCount: 16)
        catalog.assertAll(Self.designKeys)
    }

    /// 凡例の3つの文言は、差し込みの書式指定子を持ちます。
    ///
    /// 責務: `legend.below` は1つ、`legend.at_least` は1つ、`legend.range` は2つの `%@` を ja / en / es で持つことを確認します。
    func testLegendKeysKeepTheirPlaceholders() throws {
        let catalog = try LocalizableCatalogChecker()
        let expected: [String: [String]] = [
            "analysis.route.legend.below": ["@"], "analysis.route.legend.at_least": ["@"], "analysis.route.legend.range": ["@", "@"]
        ]
        for (key, specifiers) in expected {
            for language in LocalizableCatalogChecker.languages {
                let text = try XCTUnwrap(catalog.translation(key, language: language), "\(key) [\(language)]")
                XCTAssertEqual(LocalizableCatalogChecker.specifiers(in: text), specifiers, "\(key) [\(language)]")
            }
        }
    }

    /// カタログの `analysis.route.` と `analysis.mode.route` のキーが、すべて訳されています。
    ///
    /// 責務: 製品コードが使わないキーも含め、カタログ側から数えて確認します。
    func testEveryCatalogRouteKeyIsTranslated() throws {
        let catalog = try LocalizableCatalogChecker()
        let keys = catalog.catalogKeys(prefix: "analysis.route.") + catalog.catalogKeys(prefix: "analysis.mode.route")
        XCTAssertFalse(keys.isEmpty, "analysis.route.* のキーがカタログに無い")
        catalog.assertAll(keys)
    }

    /// 製品コードが返すキーを、カタログの `analysis.route.` のキーが覆っています。
    ///
    /// 責務: 指標のキーと設計書のキーがすべてカタログの一覧に含まれることを確認します。
    func testCatalogCoversEveryProducedKey() throws {
        let catalog = Set(try LocalizableCatalogChecker().catalogKeys(prefix: "analysis.route."))
        let produced = metricKeys() + Self.designKeys
        XCTAssertTrue(Set(produced).isSubset(of: catalog), "カタログに無い: \(Set(produced).subtracting(catalog).sorted())")
    }
}
