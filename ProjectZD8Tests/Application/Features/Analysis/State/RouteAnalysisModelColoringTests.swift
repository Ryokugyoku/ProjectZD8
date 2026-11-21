import Foundation
import XCTest
@testable import ProjectZD8

/// 解析の走行ルートのモデルの、PID の時系列の受け取り・色分けの選択肢・指標の切り替え・重ね合わせを検証します。
@MainActor
final class RouteAnalysisModelColoringTests: XCTestCase {
    private typealias Values = RouteAnalysisModelTestValues

    /// モデルと部品の組です。
    private var harness = RouteAnalysisModelHarness()

    /// 責務: 止めた読み込みを必ず再開し、終わらないテストを残しません。
    override func tearDown() async throws {
        harness.port.gate.releaseAll()
        try await super.tearDown()
    }

    /// 車速で色分けされるまで待ちます。
    ///
    /// 責務: 期限(2秒)内に、車速が選ばれ、指標のグラフと区分0・区分2の線がそろうのを待ちます。
    private func waitForSpeedColoring() async {
        await harness.waitUntil("speed coloring") {
            self.harness.state.selectedColorSource == .metric(.vehicleSpeed)
                && self.harness.state.metricChart != nil
                && self.harness.lineCategories == [.ramp(step: 0), .ramp(step: 2)]
        }
    }

    /// 選択肢を引きます。
    ///
    /// 責務: 現在の選択肢から、指定の出どころのものを探します。
    /// - Parameter source: 出どころ。
    /// - Returns: 選択肢。
    private func option(_ source: RouteAnalysisColorSource) -> RouteAnalysisColorSourceOption? {
        harness.state.colorSourceOptions.first { $0.source == source }
    }

    /// 責務: 読み込み済みの後に届いた時系列で、選択肢・既定の指標・色分け・指標のグラフがそろうことを確かめます。
    func testTimelineAfterLoadBuildsColoring() async {
        let session = DrivingRouteTestValues.session()
        await harness.showReadyRoute(session)

        harness.model.send(.timelineLoaded(session.id, Values.speedSamples()))

        await waitForSpeedColoring()
        XCTAssertEqual(option(.metric(.vehicleSpeed))?.isEnabled, true)
        XCTAssertEqual(option(.metric(.engineSpeed))?.isEnabled, false)
        XCTAssertEqual(harness.state.metricChart?.points.count, 10)
        XCTAssertEqual(harness.state.layers?.hasMatchedValues, true)
    }

    /// 責務: 表示より前に届いた同じセッションの時系列も、読み込んだ後の色分けに使うことを確かめます。
    func testTimelineBeforeShowingIsUsed() async {
        let session = DrivingRouteTestValues.session()

        harness.model.send(.timelineLoaded(session.id, Values.speedSamples()))
        await harness.showReadyRoute(session)

        await waitForSpeedColoring()
    }

    /// 責務: 別のセッションの時系列は無視し、色なしのままであることを確かめます。
    func testTimelineForOtherSessionIsIgnored() async {
        let session = DrivingRouteTestValues.session()
        await harness.showReadyRoute(session)

        harness.model.send(.timelineLoaded(ConnectionSessionID(), Values.speedSamples()))
        await LocationRecordingBoundedWaiter.settle()

        XCTAssertNil(harness.state.selectedColorSource)
        XCTAssertNil(harness.state.metricChart)
        XCTAssertEqual(harness.lineCategories, [.base])
    }

    /// 責務: 4つの指標のどれも無い時系列では、選べる指標が無く、色分けの元が無い注記を出して色なしのままであることを確かめます。
    func testTimelineWithoutMetricsKeepsBaseColoring() async {
        let session = DrivingRouteTestValues.session()
        await harness.showReadyRoute(session)

        harness.model.send(.timelineLoaded(session.id, Values.samples(pid: 0x11, values: [20, 30], unit: "%")))
        await harness.waitUntil("no color source notice") { self.harness.state.noticeKeys.contains("analysis.route.notice.no_color_source") }
        await LocationRecordingBoundedWaiter.settle()

        XCTAssertTrue(harness.state.colorSourceOptions.allSatisfy { !$0.isEnabled })
        XCTAssertEqual(harness.state.noticeKeys, ["analysis.route.notice.no_color_source"])
        XCTAssertNil(harness.state.selectedColorSource)
        XCTAssertNil(harness.state.metricChart)
        XCTAssertEqual(harness.lineCategories, [.base])
    }

    /// 責務: 選べない指標(記録の無いエンジン回転)と、一覧に無い重ね合わせの選択を無視することを確かめます。
    func testSelectingUnavailableSourceIsIgnored() async {
        let session = DrivingRouteTestValues.session()
        await harness.showReadyRoute(session)
        harness.model.send(.timelineLoaded(session.id, Values.speedSamples()))
        await waitForSpeedColoring()
        let colored = harness.state

        harness.model.send(.colorSourceSelected(.metric(.engineSpeed)))
        harness.model.send(.colorSourceSelected(.overlay(id: "missing")))
        await LocationRecordingBoundedWaiter.settle()

        XCTAssertEqual(harness.state, colored)
    }

    /// 責務: 選べる別の指標を選ぶと、その指標で色と指標のグラフを作り直すことを確かめます。
    func testSelectingAvailableMetricRecolors() async {
        let session = DrivingRouteTestValues.session()
        await harness.showReadyRoute(session)
        harness.model.send(.timelineLoaded(session.id, Values.speedSamples() + Values.engineSpeedSamples()))
        await harness.waitUntil("engine option") { self.option(.metric(.engineSpeed))?.isEnabled == true }

        harness.model.send(.colorSourceSelected(.metric(.engineSpeed)))

        await harness.waitUntil("engine coloring") {
            self.harness.state.selectedColorSource == .metric(.engineSpeed)
                && self.harness.lineCategories == [.ramp(step: 0), .ramp(step: 4)]
                && self.harness.state.metricChart?.maximum == 5_000
        }
        XCTAssertEqual(harness.state.metricChart?.unit, "rpm")
    }

    /// 責務: 選んでいた指標が新しい時系列で選べなくなったら、既定(最初に選べる指標)へ戻ることを確かめます。
    func testUnavailableSelectionFallsBackToDefault() async {
        let session = DrivingRouteTestValues.session()
        await harness.showReadyRoute(session)
        harness.model.send(.timelineLoaded(session.id, Values.speedSamples() + Values.engineSpeedSamples()))
        await harness.waitUntil("engine option") { self.option(.metric(.engineSpeed))?.isEnabled == true }
        harness.model.send(.colorSourceSelected(.metric(.engineSpeed)))
        await harness.waitUntil("engine selected") { self.harness.state.selectedColorSource == .metric(.engineSpeed) }

        harness.model.send(.timelineLoaded(session.id, Values.speedSamples()))

        await waitForSpeedColoring()
        XCTAssertEqual(option(.metric(.engineSpeed))?.isEnabled, false)
    }

    /// 責務: 指標で色分けして時刻の合う値が1つも無ければ、読み込みの注記の後ろに一致なしの注記が付くことを確かめます。
    func testNoMatchingValuesAddsNotice() async {
        let session = DrivingRouteTestValues.session()
        harness.setResult(.available(Values.route(pointCount: 10), noticeKeys: ["test.notice"]), for: session)
        harness.model.send(.accountIdentifierChanged(Values.account))
        harness.model.send(.sessionShown(session))
        await harness.waitUntil("ready") { self.harness.state.phase == .ready && self.harness.state.layers != nil }

        let shifted = Values.samples(pid: 0x0D, values: [30, 30, 30], unit: "km/h", secondsOffset: 1_000)
        harness.model.send(.timelineLoaded(session.id, shifted))

        await harness.waitUntil("no match notice") {
            self.harness.state.noticeKeys == ["test.notice", "analysis.route.notice.no_matching_values"]
        }
        XCTAssertEqual(harness.state.selectedColorSource, .metric(.vehicleSpeed))
        XCTAssertEqual(harness.state.layers?.hasMatchedValues, false)
        XCTAssertEqual(harness.lineCategories, [.noValue])
    }
}
