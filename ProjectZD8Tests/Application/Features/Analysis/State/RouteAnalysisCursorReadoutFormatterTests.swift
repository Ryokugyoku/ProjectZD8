import Foundation
import XCTest
@testable import ProjectZD8

/// グラフで選んだ時刻の読み出しの整形を検証します。
@MainActor
final class RouteAnalysisCursorReadoutFormatterTests: XCTestCase {
    /// UTC 2023-11-14 22:13:20(東京では 2023-11-15 07:13:20)です。
    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    /// 時刻の文字を作ります。
    ///
    /// 責務: en_US と指定のタイムゾーンで整形します。
    private func timeText(in identifier: String) throws -> String {
        let timeZone = try XCTUnwrap(TimeZone(identifier: identifier))
        return RouteAnalysisCursorReadoutFormatter(locale: Locale(identifier: "en_US"), timeZone: timeZone).timeText(for: date)
    }

    /// 東京では、現地の時・分・秒になります。
    ///
    /// 責務: タイムゾーンが Asia/Tokyo の時の数字と日付なしを確認します。
    func testTimeTextFollowsTokyoTimeZone() throws {
        let text = try timeText(in: "Asia/Tokyo")
        XCTAssertTrue(text.contains("7:13:20"), text)
        XCTAssertFalse(text.contains("2023"), text)
        XCTAssertFalse(text.contains("11/"), text)
    }

    /// UTC では、UTC の時・分・秒になります。
    ///
    /// 責務: タイムゾーンが UTC の時の数字と日付なしを確認します。
    func testTimeTextFollowsUTCTimeZone() throws {
        let text = try timeText(in: "UTC")
        XCTAssertTrue(text.contains("10:13:20"), text)
        XCTAssertFalse(text.contains("2023"), text)
        XCTAssertFalse(text.contains("11/"), text)
    }

    /// 位置が無い時だけ、案内のキーを返します。
    ///
    /// 責務: `positionMessageKey(for:)` の位置なし・位置ありを確認します。
    func testPositionMessageKey() throws {
        let coordinate = try XCTUnwrap(GeoCoordinate(latitude: 35, longitude: 139))
        let formatter = RouteAnalysisCursorReadoutFormatter(locale: Locale(identifier: "en_US"), timeZone: .gmt)
        let without = RouteAnalysisCursor(date: date, coordinate: nil, metricValueText: "1", elevationText: "2")
        let with = RouteAnalysisCursor(date: date, coordinate: coordinate, metricValueText: nil, elevationText: nil)
        XCTAssertEqual(formatter.positionMessageKey(for: without), "analysis.route.cursor.no_position")
        XCTAssertNil(formatter.positionMessageKey(for: with))
    }
}
