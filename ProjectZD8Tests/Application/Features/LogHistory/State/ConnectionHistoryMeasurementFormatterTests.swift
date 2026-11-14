import Foundation
import XCTest
@testable import ProjectZD8

/// 接続履歴の時間・距離表示変換を検証します。
@MainActor
final class ConnectionHistoryMeasurementFormatterTests: XCTestCase {
    /// ロケール非依存の結果を得るため英語POSIXロケールを注入した変換器です。
    private let formatter: ConnectionHistoryMeasurementFormatter = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return ConnectionHistoryMeasurementFormatter(calendar: calendar, locale: Locale(identifier: "en_US_POSIX"))
    }()

    /// 3600秒未満は分だけで表示します。
    ///
    /// 責務: 0秒、1分未満、1分、3599秒の境界が分単位表記になることを確認します。
    func testDurationBelowOneHourUsesMinutesOnly() {
        XCTAssertEqual(formatter.durationText(0), "0 min")
        XCTAssertEqual(formatter.durationText(59), "0 min")
        XCTAssertEqual(formatter.durationText(60), "1 min")
        XCTAssertEqual(formatter.durationText(3_599), "59 min")
    }

    /// 3600秒以上は時と分を0埋めして表示します。
    ///
    /// 責務: 3600秒ちょうどと端数を含む値が時分表記になることを確認します。
    func testDurationFromOneHourUsesHoursAndPaddedMinutes() {
        XCTAssertEqual(formatter.durationText(3_600), "1 hr, 0 min")
        XCTAssertEqual(formatter.durationText(3_660), "1 hr, 1 min")
        XCTAssertEqual(formatter.durationText(7_322), "2 hr, 2 min")
    }

    /// 負の秒数は0分として表示します。
    ///
    /// 責務: 小さい負値と1時間相当の負値がいずれも0分へ丸められることを確認します。
    func testNegativeDurationIsClampedToZeroMinutes() {
        XCTAssertEqual(formatter.durationText(-1), "0 min")
        XCTAssertEqual(formatter.durationText(-7_200), "0 min")
    }

    /// 既定の変換器は現在カレンダーで従来と同じ設定の書式を使います。
    ///
    /// 責務: 注入なしの生成が自動更新カレンダーと現在ロケールを使うことを確認します。
    func testDefaultFormatterUsesCurrentCalendarAndLocale() {
        let defaultFormatter = ConnectionHistoryMeasurementFormatter()
        let expected = DateComponentsFormatter()
        expected.allowedUnits = [.hour, .minute]
        expected.unitsStyle = .short
        expected.zeroFormattingBehavior = .pad

        XCTAssertEqual(defaultFormatter.calendar, .autoupdatingCurrent)
        XCTAssertEqual(defaultFormatter.locale, .current)
        XCTAssertEqual(defaultFormatter.durationText(3_600), expected.string(from: 3_600))
    }

    /// 走行距離が未確定なら非対応文言を返します。
    ///
    /// 責務: `nil` 距離が `history.distance.unsupported` の文言になることを確認します。
    func testNilDistanceUsesUnsupportedText() {
        XCTAssertEqual(formatter.distanceText(nil), String(localized: "history.distance.unsupported"))
    }

    /// 1 km未満はメートルの整数で表示します。
    ///
    /// 責務: 0、1 km直前、負値がメートル表記になることを確認します。
    func testDistanceBelowOneKilometerUsesMeters() {
        XCTAssertEqual(formatter.distanceText(0), "0 m")
        XCTAssertEqual(formatter.distanceText(0.999), "999 m")
        XCTAssertEqual(formatter.distanceText(-0.5), "-500 m")
    }

    /// 1 km以上はキロメートルの小数1桁で表示します。
    ///
    /// 責務: 1.0 kmちょうどと端数を含む値がキロメートル表記になることを確認します。
    func testDistanceFromOneKilometerUsesKilometers() {
        XCTAssertEqual(formatter.distanceText(1.0), "1.0 km")
        XCTAssertEqual(formatter.distanceText(12.34), "12.3 km")
    }

    /// 距離の小数点は注入したロケールに従います。
    ///
    /// 責務: ロケール注入が数値整形へ反映されることを確認します。
    func testDistanceUsesInjectedLocaleDecimalSeparator() {
        let german = ConnectionHistoryMeasurementFormatter(locale: Locale(identifier: "de_DE"))

        XCTAssertEqual(german.distanceText(12.34), "12,3 km")
    }

    /// 終了済みセッションの記録時間は終了と開始の差です。
    ///
    /// 責務: 終了日時がある場合に差分秒数を返すことを確認します。
    func testSessionDurationUsesEndMinusStart() {
        var session = ConnectionSession(accountIdentifier: "account", startedAt: Date(timeIntervalSince1970: 100))
        session.endedAt = Date(timeIntervalSince1970: 3_700)

        XCTAssertEqual(formatter.sessionDuration(session), 3_600)
    }

    /// 終了日時が無いセッションの記録時間は0です。
    ///
    /// 責務: 未終了セッションを0秒として扱うことを確認します。
    func testSessionDurationWithoutEndIsZero() {
        let session = ConnectionSession(accountIdentifier: "account", startedAt: Date(timeIntervalSince1970: 100))

        XCTAssertEqual(formatter.sessionDuration(session), 0)
    }

    /// 終了日時が開始より前のセッションの記録時間は0です。
    ///
    /// 責務: 負の差分を0秒へ丸めることを確認します。
    func testSessionDurationWithEndBeforeStartIsZero() {
        var session = ConnectionSession(accountIdentifier: "account", startedAt: Date(timeIntervalSince1970: 100))
        session.endedAt = Date(timeIntervalSince1970: 50)

        XCTAssertEqual(formatter.sessionDuration(session), 0)
    }
}
