import Foundation
import XCTest
@testable import ProjectZD8

/// `AdapterLinkRecordingIntent` が選択を受け取った時刻を有効期限の起点として保持することを検証します。
final class AdapterLinkRecordingIntentTests: XCTestCase {
    /// 選択の時刻をそのまま保持し、時刻が同じ意思は等しく、違えば等しくありません。
    ///
    /// 責務: `selectedAt` の保持と等価性を確認します(U4 受け入れ条件 5)。
    func testKeepsSelectedAtAndComparesByIt() {
        let selectedAt = Date(timeIntervalSinceReferenceDate: 1_000)
        let intent = AdapterLinkRecordingIntent(selectedAt: selectedAt)
        XCTAssertEqual(intent.selectedAt, selectedAt)
        XCTAssertEqual(intent, AdapterLinkRecordingIntent(selectedAt: selectedAt))
        XCTAssertNotEqual(intent, AdapterLinkRecordingIntent(selectedAt: selectedAt.addingTimeInterval(0.001)))
    }
}
