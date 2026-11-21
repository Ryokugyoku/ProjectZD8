import Foundation
import XCTest
@testable import ProjectZD8

/// 一覧の行の時刻の文字列(`timeText`)の規則を検証します(設計書 §3.3、§7 TC1a)。
///
/// 24時間制の HH:mm:ss をタイムゾーンで出し、開始と終了が同じ秒なら1つ、違えば U+2013 で空白なしに結びます。
/// 期待値は 1_800_000_000 = 2027-01-15 08:00:00 UTC(17:00:00 JST)からの手計算です。
@MainActor
final class SessionRoadRegulationReviewRowFormatterTimeTests: XCTestCase {
    /// 値の短い名前です。
    private typealias Values = SessionRoadRegulationReviewTestValues

    /// ロケールとタイムゾーンを固定した formatter を作ります。
    ///
    /// 責務: 言語設定に依存しない検証対象を返します。
    /// - Parameters:
    ///   - locale: ロケール識別子。
    ///   - timeZone: タイムゾーン。省くと日本時間。
    /// - Returns: formatter。
    private func formatter(
        _ locale: String = "en_US_POSIX",
        timeZone: TimeZone = SessionRoadRegulationReviewTestValues.tokyo
    ) -> SessionRoadRegulationReviewRowFormatter {
        SessionRoadRegulationReviewRowFormatter(
            locale: Locale(identifier: locale),
            timeZone: timeZone,
            localize: Values.bracketLocalize
        )
    }

    /// 基準からの秒の範囲の時刻の文字列を返します。
    ///
    /// 責務: 秒の範囲を時刻の範囲にして整形します。
    /// - Parameters:
    ///   - seconds: 基準からの秒の範囲。
    ///   - formatter: 検証対象。
    /// - Returns: 時刻の文字列。
    private func text(_ seconds: ClosedRange<TimeInterval>, _ formatter: SessionRoadRegulationReviewRowFormatter) -> String {
        formatter.timeText(Values.date(seconds.lowerBound)...Values.date(seconds.upperBound))
    }

    /// 責務: 開始と終了が同じ時刻なら、日本時間の 17:00:00 を1つだけ出すことを確かめます。
    func testSameInstantShowsOneTime() {
        XCTAssertEqual(text(0...0, formatter()), "17:00:00")
    }

    /// 責務: 0.4 秒しか違わず同じ秒に入る時は、1つだけ出すことを確かめます。
    func testSubSecondDifferenceInSameSecondShowsOneTime() {
        XCTAssertEqual(text(0...0.4, formatter()), "17:00:00")
    }

    /// 責務: 差が1秒未満でも、表示の秒の境目をまたげば(0.7 秒と 1.3 秒)2つ出すことを確かめます。
    func testSubSecondDifferenceAcrossSecondBoundaryShowsRange() {
        XCTAssertEqual(text(0.7...1.3, formatter()), "17:00:00\u{2013}17:00:01")
    }

    /// 責務: 同じ秒の中の 0.1 秒と 0.9 秒は、1つだけ出すことを確かめます。
    func testEarlyAndLateInSameSecondShowsOneTime() {
        XCTAssertEqual(text(0.1...0.9, formatter()), "17:00:00")
    }

    /// 責務: 1秒違う時は「開始–終了」を U+2013 で空白なしに結ぶことを確かめます。
    func testOneSecondDifferenceShowsRange() {
        XCTAssertEqual(text(0...1, formatter()), "17:00:00\u{2013}17:00:01")
    }

    /// 責務: 35 秒の区間を「17:00:00–17:00:35」と出すことを確かめます。
    func testRangeOfSeveralSeconds() {
        XCTAssertEqual(text(0...35, formatter()), "17:00:00\u{2013}17:00:35")
    }

    /// 責務: 0時台を 24時間制の「00:」で出すことを確かめます(2027-01-16 00:05:09 JST = 基準 + 25,509 秒)。
    func testMidnightHourUsesTwentyFourHourClock() {
        XCTAssertEqual(text(25_509...25_509, formatter()), "00:05:09")
    }

    /// 責務: 日付をまたぐ範囲を「23:59:59–00:00:01」と出すことを確かめます(基準 + 25,199 秒 〜 + 25,201 秒)。
    func testRangeCrossingMidnight() {
        XCTAssertEqual(text(25_199...25_201, formatter()), "23:59:59\u{2013}00:00:01")
    }

    /// 責務: 12時間制を好むロケール(en_US)でも、午前・午後を付けずに 24時間制で出すことを確かめます。
    func testTwelveHourLocaleStillUsesTwentyFourHourClock() {
        XCTAssertEqual(text(0...35, formatter("en_US")), "17:00:00\u{2013}17:00:35")
    }

    /// 責務: ja_JP でも同じ書式で出すことを確かめます。
    func testJapaneseLocale() {
        XCTAssertEqual(text(0...35, formatter("ja_JP")), "17:00:00\u{2013}17:00:35")
    }

    /// 責務: 注入したタイムゾーンで時刻を出すこと(UTC なら 08:00:00)を確かめます。
    func testUsesInjectedTimeZone() {
        guard let utc = TimeZone(identifier: "UTC") else {
            return XCTFail("UTC を作れません")
        }

        XCTAssertEqual(text(0...0, formatter(timeZone: utc)), "08:00:00")
    }
}
