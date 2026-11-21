import Foundation
import XCTest
@testable import ProjectZD8

/// 色分けに選べる指標と重ね合わせの一覧、既定の選択を決める規則を検証します(設計書 §3.4、§6 `metric.unavailable`)。
@MainActor
final class RouteAnalysisColorSourceCatalogTests: XCTestCase {
    /// 検証対象です。
    private let catalog = RouteAnalysisColorSourceCatalog()
    /// 記録が無い指標の理由のキーです。
    private let unavailableKey = "analysis.route.metric.unavailable"

    /// 1件の値を持つ指標の列を作ります。
    ///
    /// 責務: 空でない値の列を返します。
    /// - Parameter metric: 指標。
    /// - Returns: 値の列。
    private func filled(_ metric: RouteAnalysisColorMetric) -> RouteAnalysisValueSeries {
        RouteAnalysisValueSeriesFixtures.series([(0, 10)], metric: metric, unit: metric.fallbackUnit)
    }

    /// 重ね合わせを作ります。
    ///
    /// 責務: ID と題名のキーだけを持つ重ね合わせを返します。
    /// - Parameter id: 重ね合わせの ID。
    /// - Returns: 重ね合わせ。
    private func overlay(_ id: String) -> RouteAnalysisOverlay {
        RouteAnalysisOverlay(id: id, titleKey: "test.overlay.\(id)", runs: [], legend: [], highlightedTimeRanges: [])
    }

    /// 選択肢を作ります。
    ///
    /// 責務: 既定の選択の検証のため、指定の出どころと可否の選択肢を返します。
    /// - Parameters:
    ///   - source: 出どころ。
    ///   - isEnabled: 選べるか。
    /// - Returns: 選択肢。
    private func option(_ source: RouteAnalysisColorSource, enabled isEnabled: Bool) -> RouteAnalysisColorSourceOption {
        RouteAnalysisColorSourceOption(source: source, titleKey: "test.option", isEnabled: isEnabled, disabledReasonKey: isEnabled ? nil : unavailableKey)
    }

    /// 指標の選択肢を引きます。
    ///
    /// 責務: 一覧から指定の指標の選択肢を探します。
    /// - Parameters:
    ///   - metric: 指標。
    ///   - options: 一覧。
    /// - Returns: 選択肢。
    private func option(for metric: RouteAnalysisColorMetric, in options: [RouteAnalysisColorSourceOption]) -> RouteAnalysisColorSourceOption? {
        options.first { $0.source == .metric(metric) }
    }

    /// 責務: 値のある指標は選べて理由を持たず、題名が指標のキーであることを確かめます。
    func testMetricWithValuesIsEnabled() {
        let options = catalog.options(valueSeries: [.engineSpeed: filled(.engineSpeed)], overlays: [])

        let engine = option(for: .engineSpeed, in: options)
        XCTAssertEqual(engine?.isEnabled, true)
        XCTAssertNil(engine?.disabledReasonKey)
        XCTAssertEqual(engine?.titleKey, RouteAnalysisColorMetric.engineSpeed.titleKey)
        XCTAssertEqual(engine?.id, .metric(.engineSpeed))
    }

    /// 責務: 列の無い指標は、選べない選択肢として理由のキーを持って並ぶことを確かめます(車速を GPS の速さで代用しない)。
    func testMetricWithoutSeriesIsDisabledWithReason() {
        let options = catalog.options(valueSeries: [.engineSpeed: filled(.engineSpeed)], overlays: [])

        let speed = option(for: .vehicleSpeed, in: options)
        XCTAssertEqual(speed?.isEnabled, false)
        XCTAssertEqual(speed?.disabledReasonKey, unavailableKey)
        XCTAssertEqual(speed?.titleKey, RouteAnalysisColorMetric.vehicleSpeed.titleKey)
    }

    /// 責務: 空の列しかない指標も、選べず理由のキーを持つことを確かめます。
    func testMetricWithEmptySeriesIsDisabled() {
        let empty = RouteAnalysisValueSeries(pid: RouteAnalysisColorMetric.engineLoad.pid, unit: "%", samples: [])

        let options = catalog.options(valueSeries: [.engineLoad: empty], overlays: [])

        XCTAssertEqual(option(for: .engineLoad, in: options)?.isEnabled, false)
        XCTAssertEqual(option(for: .engineLoad, in: options)?.disabledReasonKey, unavailableKey)
    }

    /// 責務: 重ね合わせが無ければ、4つの指標が `allCases` の順にちょうど1つずつ並ぶことを確かめます。
    func testEveryMetricIsListedOnce() {
        let options = catalog.options(valueSeries: [:], overlays: [])

        XCTAssertEqual(options.map(\.source), RouteAnalysisColorMetric.allCases.map { RouteAnalysisColorSource.metric($0) })
        XCTAssertTrue(options.allSatisfy { !$0.isEnabled })
    }

    /// 責務: 重ね合わせは指標の後ろに、渡した順で、選べる選択肢として並ぶことを確かめます。
    func testOverlaysFollowMetricsInGivenOrder() {
        let options = catalog.options(valueSeries: [.vehicleSpeed: filled(.vehicleSpeed)], overlays: [overlay("b"), overlay("a")])

        XCTAssertEqual(options.count, 6)
        XCTAssertEqual(options.suffix(2).map(\.source), [.overlay(id: "b"), .overlay(id: "a")])
        XCTAssertEqual(options.suffix(2).map(\.titleKey), ["test.overlay.b", "test.overlay.a"])
        XCTAssertTrue(options.suffix(2).allSatisfy { $0.isEnabled && $0.disabledReasonKey == nil })
        XCTAssertTrue(options.prefix(4).allSatisfy { if case .metric = $0.source { true } else { false } })
    }

    /// 責務: 既定は、並びの中で最初に選べる指標になることを確かめます。
    func testDefaultIsFirstEnabledMetric() {
        let options = [
            option(.metric(.vehicleSpeed), enabled: false),
            option(.metric(.engineSpeed), enabled: true),
            option(.metric(.engineLoad), enabled: true)
        ]

        XCTAssertEqual(catalog.defaultSource(in: options), .metric(.engineSpeed))
    }

    /// 責務: 前に選べる重ね合わせがあっても、既定にしないことを確かめます。
    func testDefaultSkipsOverlays() {
        let options = [
            option(.overlay(id: "x"), enabled: true),
            option(.metric(.engineLoad), enabled: false),
            option(.metric(.coolantTemperature), enabled: true)
        ]

        XCTAssertEqual(catalog.defaultSource(in: options), .metric(.coolantTemperature))
    }

    /// 責務: 選べるのが重ね合わせだけなら、既定は `nil` になることを確かめます。
    func testDefaultIsNilWhenOnlyOverlaysAreEnabled() {
        let options = [option(.metric(.vehicleSpeed), enabled: false), option(.overlay(id: "x"), enabled: true)]

        XCTAssertNil(catalog.defaultSource(in: options))
    }

    /// 責務: 選択肢が空なら、既定は `nil` になることを確かめます。
    func testDefaultIsNilForEmptyOptions() {
        XCTAssertNil(catalog.defaultSource(in: []))
    }

    /// 責務: 一覧から既定を選ぶと、値のある唯一の指標になることを確かめます(並びの順に依存しない組み合わせ)。
    func testDefaultFromCatalogPicksOnlyFilledMetric() {
        let options = catalog.options(valueSeries: [.coolantTemperature: filled(.coolantTemperature)], overlays: [overlay("a")])

        XCTAssertEqual(catalog.defaultSource(in: options), .metric(.coolantTemperature))
    }

    /// 責務: 範囲(runs)が空の重ね合わせも、選べる選択肢で理由を持たないことを確かめます。
    func testOverlayWithoutRunsIsEnabled() {
        let options = catalog.options(valueSeries: [:], overlays: [overlay("empty")])

        let entry = options.first { $0.source == .overlay(id: "empty") }
        XCTAssertEqual(entry?.isEnabled, true)
        XCTAssertNil(entry?.disabledReasonKey)
    }
}
