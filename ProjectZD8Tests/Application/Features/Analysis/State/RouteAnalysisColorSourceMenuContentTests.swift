import Foundation
import XCTest
@testable import ProjectZD8

/// 色分けの切替の部品に出す見出しと「選べない」案内の決定を検証します。
@MainActor
final class RouteAnalysisColorSourceMenuContentTests: XCTestCase {
    /// 車速の選択肢(選べる)です。
    private let speed = RouteAnalysisColorSourceMenuContentTests.option(.metric(.vehicleSpeed), title: "speed", enabled: true, reason: nil)
    /// 回転の選択肢(選べない・理由あり)です。
    private let rpm = RouteAnalysisColorSourceMenuContentTests.option(.metric(.engineSpeed), title: "rpm", enabled: false, reason: "rpm.reason")
    /// 負荷の選択肢(選べない・理由なし)です。
    private let load = RouteAnalysisColorSourceMenuContentTests.option(.metric(.engineLoad), title: "load", enabled: false, reason: nil)
    /// 水温の選択肢(選べない・理由あり)です。
    private let water = RouteAnalysisColorSourceMenuContentTests.option(.metric(.coolantTemperature), title: "water", enabled: false, reason: "water.reason")

    /// 選択肢を作ります。
    ///
    /// 責務: 引数どおりの選択肢を返します。
    private static func option(
        _ source: RouteAnalysisColorSource, title: String, enabled: Bool, reason: String?
    ) -> RouteAnalysisColorSourceOption {
        RouteAnalysisColorSourceOption(source: source, titleKey: title, isEnabled: enabled, disabledReasonKey: reason)
    }

    /// 選択肢が空なら切替の部品を出しません。
    ///
    /// 責務: `isVisible` の空と非空を確認します。
    func testIsVisibleOnlyWhenOptionsExist() {
        XCTAssertFalse(RouteAnalysisColorSourceMenuContent(options: [], selectedSource: nil).isVisible)
        XCTAssertTrue(RouteAnalysisColorSourceMenuContent(options: [speed], selectedSource: nil).isVisible)
    }

    /// 選んでいる選択肢の名前を返します。
    ///
    /// 責務: `selectedTitleKey` の一致・未選択・一致なしを確認します。
    func testSelectedTitleKey() {
        let options = [speed, rpm]
        XCTAssertEqual(RouteAnalysisColorSourceMenuContent(options: options, selectedSource: .metric(.engineSpeed)).selectedTitleKey, "rpm")
        XCTAssertNil(RouteAnalysisColorSourceMenuContent(options: options, selectedSource: nil).selectedTitleKey)
        XCTAssertNil(RouteAnalysisColorSourceMenuContent(options: options, selectedSource: .overlay(id: "none")).selectedTitleKey)
        XCTAssertNil(RouteAnalysisColorSourceMenuContent(options: [], selectedSource: .metric(.vehicleSpeed)).selectedTitleKey)
    }

    /// 選べない選択肢の名前を、順序どおりに返します。
    ///
    /// 責務: `unavailableTitleKeys` の絞り込みと順序を確認します。
    func testUnavailableTitleKeysKeepOrder() {
        let content = RouteAnalysisColorSourceMenuContent(options: [water, speed, rpm, load], selectedSource: nil)
        XCTAssertEqual(content.unavailableTitleKeys, ["water", "rpm", "load"])
        XCTAssertEqual(RouteAnalysisColorSourceMenuContent(options: [speed], selectedSource: nil).unavailableTitleKeys, [])
    }

    /// 選べない理由は、選べず理由を持つ最初の選択肢のものです。
    ///
    /// 責務: `unavailableReasonKey` の先頭選択・理由なしの読み飛ばし・無しを確認します。
    func testUnavailableReasonKeyPicksFirstWithReason() {
        XCTAssertEqual(
            RouteAnalysisColorSourceMenuContent(options: [speed, load, water, rpm], selectedSource: nil).unavailableReasonKey,
            "water.reason"
        )
        XCTAssertNil(RouteAnalysisColorSourceMenuContent(options: [speed, load], selectedSource: nil).unavailableReasonKey)
        XCTAssertNil(RouteAnalysisColorSourceMenuContent(options: [], selectedSource: nil).unavailableReasonKey)
    }

    /// 選べる選択肢は、理由を持っていても案内に使いません。
    ///
    /// 責務: 選べる選択肢の理由が無視されることを確認します。
    func testEnabledOptionReasonIsIgnored() {
        let enabledWithReason = Self.option(.metric(.vehicleSpeed), title: "speed", enabled: true, reason: "ignored")
        let content = RouteAnalysisColorSourceMenuContent(options: [enabledWithReason], selectedSource: nil)
        XCTAssertNil(content.unavailableReasonKey)
        XCTAssertEqual(content.unavailableTitleKeys, [])
    }

    /// 選択肢が選ばれているかは、色分けの元の一致で決まります。
    ///
    /// 責務: `isSelected(_:)` の一致・不一致・未選択を確認します。
    func testIsSelected() {
        let content = RouteAnalysisColorSourceMenuContent(options: [speed, rpm], selectedSource: .metric(.vehicleSpeed))
        XCTAssertTrue(content.isSelected(speed))
        XCTAssertFalse(content.isSelected(rpm))
        XCTAssertFalse(RouteAnalysisColorSourceMenuContent(options: [speed], selectedSource: nil).isSelected(speed))
    }
}
