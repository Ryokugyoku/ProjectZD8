import Foundation
import XCTest
@testable import ProjectZD8

/// 解析の走行ルートのモデルで、重ね合わせ(軌跡の区間 → 分類)の受け取り・選択・保持を検証します(設計書 §1-4、§3.4)。
@MainActor
final class RouteAnalysisModelOverlayTests: XCTestCase {
    private typealias Values = RouteAnalysisModelTestValues

    /// モデルと部品の組です。
    private var harness = RouteAnalysisModelHarness()

    /// 責務: 止めた読み込みを必ず再開し、終わらないテストを残しません。
    override func tearDown() async throws {
        harness.port.gate.releaseAll()
        try await super.tearDown()
    }

    /// 重ね合わせの選択肢を引きます。
    ///
    /// 責務: 現在の選択肢から、テストの重ね合わせのものを探します。
    /// - Returns: 選択肢。
    private func overlayOption() -> RouteAnalysisColorSourceOption? {
        harness.state.colorSourceOptions.first { $0.source == .overlay(id: Values.overlayID) }
    }

    /// 責務: 重ね合わせが届くと選択肢に加わり、選ぶとその分類の線・強調の線・強調の時刻の範囲が入り、指標のグラフが消えることを確かめます。
    func testOverlayCanBeAddedAndSelected() async {
        let session = DrivingRouteTestValues.session()
        let overlay = Values.overlay()
        await harness.showReadyRoute(session)
        harness.model.send(.timelineLoaded(session.id, Values.speedSamples()))
        await harness.waitUntil("speed chart") { self.harness.state.metricChart != nil }

        harness.model.send(.overlaysChanged([overlay]))
        await harness.waitUntil("overlay option") { self.overlayOption() != nil }
        harness.model.send(.colorSourceSelected(.overlay(id: overlay.id)))

        await harness.waitUntil("overlay coloring") {
            self.harness.state.selectedColorSource == .overlay(id: overlay.id)
                && self.harness.lineCategories.contains(.tone(.caution))
        }
        XCTAssertEqual(harness.state.highlightedTimeRanges, overlay.highlightedTimeRanges)
        XCTAssertEqual(harness.state.layers?.lines.contains(where: \.isEmphasized), true)
        XCTAssertEqual(harness.state.layers?.legend, overlay.legend)
        XCTAssertNil(harness.state.metricChart)
    }

    /// 責務: 読み込みより前に届いた重ね合わせも、読み込んだ後の選択肢に使うことを確かめます。
    func testOverlayBeforeLoadIsKept() async {
        let session = DrivingRouteTestValues.session()

        harness.model.send(.overlaysChanged([Values.overlay()]))
        await harness.showReadyRoute(session)

        await harness.waitUntil("overlay option") { self.overlayOption()?.isEnabled == true }
    }

    /// 責務: 別のセッションへ切り替えても、置き換えるまで重ね合わせを保持することを確かめます。
    func testOverlayPersistsAcrossSessions() async {
        harness.model.send(.overlaysChanged([Values.overlay()]))
        await harness.showReadyRoute(DrivingRouteTestValues.session())
        await harness.waitUntil("overlay option") { self.overlayOption() != nil }

        await harness.showReadyRoute(DrivingRouteTestValues.session())

        await harness.waitUntil("overlay option after switch") { self.overlayOption() != nil }
    }

    /// 責務: 閉じると、受け取った時系列と重ね合わせを捨て、再び表示しても使わないことを確かめます。
    func testDismissDiscardsTimelineAndOverlays() async {
        let session = DrivingRouteTestValues.session()
        harness.model.send(.overlaysChanged([Values.overlay()]))
        harness.model.send(.timelineLoaded(session.id, Values.speedSamples()))
        await harness.showReadyRoute(session)
        await harness.waitUntil("colored") { self.harness.state.selectedColorSource == .metric(.vehicleSpeed) }

        harness.model.send(.dismissed)
        await harness.waitUntil("reset") { self.harness.state == RouteAnalysisState() }
        await harness.showReadyRoute(session)
        await LocationRecordingBoundedWaiter.settle()

        XCTAssertNil(overlayOption())
        XCTAssertNil(harness.state.selectedColorSource)
        XCTAssertEqual(harness.lineCategories, [.base])
    }
}
