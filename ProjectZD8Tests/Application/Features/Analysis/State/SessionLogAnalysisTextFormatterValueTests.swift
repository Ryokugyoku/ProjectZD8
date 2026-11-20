import Foundation
import XCTest
@testable import ProjectZD8

/// 解析画面の数値・時間・距離の文字列整形を検証します。
@MainActor
final class SessionLogAnalysisTextFormatterValueTests: XCTestCase {
    /// 検証対象の解析画面向け整形です。
    private let formatter = SessionLogAnalysisTextFormatter()
    /// 「取得なし」の文言です。
    private let unavailable = String(localized: "analysis.value.unavailable")

    /// 59秒は秒だけ、60秒からは分と秒で表します。
    ///
    /// 責務: 秒/分秒の境界(59 と 60)を確認します。
    func testDurationTextSwitchesFromSecondsToMinutesAtSixty() {
        XCTAssertEqual(formatter.durationText(59), abbreviated(59, [.second]))
        XCTAssertEqual(formatter.durationText(60), abbreviated(60, [.minute, .second]))
        XCTAssertNotEqual(formatter.durationText(59), formatter.durationText(60))
    }

    /// 3599秒は分と秒、3600秒からは時と分で表します。
    ///
    /// 責務: 分秒/時分の境界(3599 と 3600)を確認します。
    func testDurationTextSwitchesFromMinutesToHoursAtOneHour() {
        XCTAssertEqual(formatter.durationText(3_599), abbreviated(3_599, [.minute, .second]))
        XCTAssertEqual(formatter.durationText(3_600), abbreviated(3_600, [.hour, .minute]))
        XCTAssertNotEqual(formatter.durationText(3_599), formatter.durationText(3_600))
    }

    /// 時分は最大2単位で、秒を含みません。
    ///
    /// 責務: 1時間超の表記が2単位に収まることを確認します。
    func testDurationTextLimitsToTwoUnits() {
        XCTAssertEqual(formatter.durationText(3_725), abbreviated(3_725, [.hour, .minute]))
        XCTAssertEqual(formatter.durationText(125), abbreviated(125, [.minute, .second]))
    }

    /// 数値は小数1桁までで、単位を空白で続けます。
    ///
    /// 責務: 小数の丸めと単位の連結を確認します(桁だけを比べ、小数点記号は比較しない)。
    func testMeasurementTextRoundsToOneFractionDigitWithUnit() {
        XCTAssertEqual(digits(formatter.measurementText(12.34, unit: "km")), "123")
        XCTAssertEqual(digits(formatter.measurementText(5, unit: "km")), "5")
        XCTAssertEqual(digits(formatter.measurementText(12.96, unit: "km")), "13")
        XCTAssertEqual(digits(formatter.measurementText(0, unit: "km")), "0")
        XCTAssertTrue(formatter.measurementText(12.34, unit: "km").hasSuffix(" km"))
        XCTAssertTrue(formatter.measurementText(7, unit: "°C").hasSuffix(" °C"))
    }

    /// 数値帯は下限と上限を書式キーへ入れます。
    ///
    /// 責務: 速度帯・回転域の書式キーで下限・上限の順に並ぶことを確認します。
    func testBandTextEmbedsLowerAndUpperBound() {
        let speed = SessionDurationBand(lowerBound: 20, upperBound: 30, duration: 1, proportion: 1)
        let rpm = SessionDurationBand(lowerBound: 1_000, upperBound: 1_500, duration: 1, proportion: 1)

        XCTAssertEqual(digits(formatter.bandText(speed, key: "analysis.overview.speed_band")), "2030")
        XCTAssertEqual(digits(formatter.bandText(rpm, key: "analysis.overview.rpm_band")), "10001500")
    }

    /// 統計は最新・最小・平均・最大の順で単位つきです。
    ///
    /// 責務: 1行の統計文字列の値の順序と単位を確認します。
    func testStatisticsTextOrdersLatestMinAverageMaxWithUnit() {
        let series = TestSessionLogAnalysisFixtures.makeSeries(service: 0x01, pid: 0x0B, unit: "kPa")
        let text = formatter.statisticsText(series)

        XCTAssertEqual(digits(text), "11223344")
        XCTAssertTrue(text.contains("kPa"))
    }

    /// 進行中のセッション時間は専用の文言です。
    ///
    /// 責務: 終了時刻が無い場合の表示を確認します。
    func testSessionDurationTextInProgress() {
        let session = TestSessionLogAnalysisFixtures.makeSession(end: nil)

        XCTAssertEqual(formatter.sessionDurationText(session), String(localized: "analysis.value.in_progress"))
    }

    /// 終了済みのセッション時間は経過秒を時間表記にします。
    ///
    /// 責務: 開始から終了までの経過時間が `durationText` と同じ表記になることを確認します。
    func testSessionDurationTextUsesElapsedTime() {
        let session = TestSessionLogAnalysisFixtures.makeSession(start: 1_000, end: 1_125)

        XCTAssertEqual(formatter.sessionDurationText(session), formatter.durationText(125))
        XCTAssertNotEqual(formatter.sessionDurationText(session), String(localized: "analysis.value.in_progress"))
    }

    /// 終了が開始より前でも負の時間にせず 0 へ切り詰めます。
    ///
    /// 責務: 負の経過時間の切り詰めと、0 秒ちょうどの扱いを確認します。
    func testSessionDurationTextClampsNegativeToZero() {
        let negative = TestSessionLogAnalysisFixtures.makeSession(start: 1_000, end: 900)
        let zero = TestSessionLogAnalysisFixtures.makeSession(start: 1_000, end: 1_000)

        XCTAssertEqual(formatter.sessionDurationText(negative), formatter.durationText(0))
        XCTAssertEqual(formatter.sessionDurationText(zero), formatter.durationText(0))
    }

    /// 推定走行時間が無ければ「取得なし」です。
    ///
    /// 責務: nil、0、正の値の3ケースを確認します。
    func testMovingDurationText() {
        let none = TestSessionLogAnalysisFixtures.makeSummary(movingDuration: nil, distance: nil)
        let zero = TestSessionLogAnalysisFixtures.makeSummary(movingDuration: 0, distance: nil)
        let value = TestSessionLogAnalysisFixtures.makeSummary(movingDuration: 90, distance: nil)

        XCTAssertEqual(formatter.movingDurationText(none), unavailable)
        XCTAssertEqual(formatter.movingDurationText(zero), formatter.durationText(0))
        XCTAssertEqual(formatter.movingDurationText(value), formatter.durationText(90))
    }

    /// 記録済みの距離差があれば、それを km で表示します。
    ///
    /// 責務: セッション記録の距離が推定より優先されることを確認します。
    func testDistanceTextPrefersRecordedDistance() {
        let session = TestSessionLogAnalysisFixtures.makeSession(startingOdometer: 1_000, endingOdometer: 1_012.34)
        let summary = TestSessionLogAnalysisFixtures.makeSummary(movingDuration: nil, distance: 99)

        let text = formatter.distanceText(session: session, summary: summary)

        XCTAssertEqual(digits(text), "123")
        XCTAssertTrue(text.hasSuffix(" km"))
    }

    /// 記録が無ければ推定距離を「約」つきの書式で表示します。
    ///
    /// 責務: 推定距離の書式(小数1桁)を確認します。
    func testDistanceTextUsesEstimatedDistanceWhenNotRecorded() {
        let session = TestSessionLogAnalysisFixtures.makeSession()
        let summary = TestSessionLogAnalysisFixtures.makeSummary(movingDuration: nil, distance: 5.26)

        let text = formatter.distanceText(session: session, summary: summary)

        XCTAssertEqual(digits(text), "53")
        XCTAssertTrue(text.contains("km"))
        XCTAssertNotEqual(text, formatter.measurementText(5.26, unit: "km"))
    }

    /// 終了時の距離が開始より小さい(記録として不正)なら推定を使います。
    ///
    /// 責務: 不正な距離差が記録済み扱いにならないことを確認します。
    func testDistanceTextIgnoresInvalidRecordedDistance() {
        let session = TestSessionLogAnalysisFixtures.makeSession(startingOdometer: 1_000, endingOdometer: 900)
        let summary = TestSessionLogAnalysisFixtures.makeSummary(movingDuration: nil, distance: 5.26)

        XCTAssertEqual(digits(formatter.distanceText(session: session, summary: summary)), "53")
    }

    /// 記録も推定も無ければ「取得なし」です。
    ///
    /// 責務: 距離の3分岐目を確認します。
    func testDistanceTextUnavailable() {
        let session = TestSessionLogAnalysisFixtures.makeSession()
        let summary = TestSessionLogAnalysisFixtures.makeSummary(movingDuration: nil, distance: nil)

        XCTAssertEqual(formatter.distanceText(session: session, summary: summary), unavailable)
    }

    /// 距離の見出しは、記録の有無で切り替わります。
    ///
    /// 責務: 記録済み・未記録・不正な記録の見出しキーを確認します。
    func testDistanceTitleKey() {
        let recorded = TestSessionLogAnalysisFixtures.makeSession(startingOdometer: 10, endingOdometer: 20)
        let missing = TestSessionLogAnalysisFixtures.makeSession()
        let invalid = TestSessionLogAnalysisFixtures.makeSession(startingOdometer: 20, endingOdometer: 10)

        XCTAssertEqual(formatter.distanceTitleKey(recorded), "analysis.overview.distance")
        XCTAssertEqual(formatter.distanceTitleKey(missing), "analysis.overview.estimated_distance")
        XCTAssertEqual(formatter.distanceTitleKey(invalid), "analysis.overview.estimated_distance")
    }

    /// 文字列から数字だけを取り出します。
    ///
    /// 責務: 小数点や桁区切りなどのロケール差を除いて桁を比較できるようにします。
    /// - Parameter text: 対象の文字列。
    /// - Returns: 数字だけを順に連結した文字列。
    private func digits(_ text: String) -> String {
        text.filter(\.isNumber)
    }

    /// 仕様の単位構成で秒数を省略表記にします。
    ///
    /// 責務: 境界ごとに決まっている単位構成(最大2単位)での期待値を作ります。
    /// - Parameters:
    ///   - seconds: 秒数。
    ///   - units: 表示する単位。
    /// - Returns: 省略表記の文字列。
    private func abbreviated(_ seconds: TimeInterval, _ units: NSCalendar.Unit) -> String {
        let reference = DateComponentsFormatter()
        reference.allowedUnits = units
        reference.unitsStyle = .abbreviated
        reference.maximumUnitCount = 2
        return reference.string(from: seconds) ?? ""
    }
}
