#if os(iOS)
import SwiftUI
import XCTest
@testable import ProjectZD8

/// 共通の状態トーンからiOS表示色への対応を検証します。
@MainActor
final class ConnectionHistoryStatusToneIOSPresentationTests: XCTestCase {
    /// 各トーンは置換前の画面と同じ色になります。
    ///
    /// 責務: neutral / caution / positive / critical / informative の全分岐を確認します。
    func testEachToneMapsToPreviousColor() {
        XCTAssertEqual(ConnectionHistoryStatusTone.neutral.color, .secondary)
        XCTAssertEqual(ConnectionHistoryStatusTone.caution.color, .orange)
        XCTAssertEqual(ConnectionHistoryStatusTone.positive.color, .green)
        XCTAssertEqual(ConnectionHistoryStatusTone.critical.color, .red)
        XCTAssertEqual(ConnectionHistoryStatusTone.informative.color, .blue)
    }
}
#endif
