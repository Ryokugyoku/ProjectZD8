import Foundation
import XCTest
@testable import ProjectZD8

/// `RecordingSessionLiveActivityMetricFormatter` の整数への丸め・地域設定の桁区切り・未取得と有限でない値の扱いを検証します。
///
/// 仕様: U5 受け入れ条件 10・13(B14。表示の書式は変えない)。
final class RecordingSessionLiveActivityMetricFormatterTests: XCTestCase {
    /// 書式の確認に使う地域設定です。
    private let english = Locale(identifier: "en_US")

    /// 整形します。
    ///
    /// 責務: 指定の地域設定で整形します。
    private func format(_ metric: RecordingSessionActivityAttributes.Metric, locale: Locale? = nil) -> String? {
        RecordingSessionLiveActivityMetricFormatter.formattedValue(of: metric, locale: locale ?? english)
    }

    /// 取得済みの値は小数を丸めた整数表記になります。
    ///
    /// 責務: 0・42.4・42.6・-7.2 の丸めを確認します。
    func testRoundsToInteger() {
        XCTAssertEqual(format(.value(0)), "0")
        XCTAssertEqual(format(.value(42.4)), "42")
        XCTAssertEqual(format(.value(42.6)), "43")
        XCTAssertEqual(format(.value(-7.2)), "-7")
    }

    /// 桁区切りは地域設定に従います。
    ///
    /// 責務: 1234.6 が en_US で "1,235"、de_DE で "1.235"、ja_JP で "1,235" になることを確認します。
    func testUsesLocaleGrouping() {
        XCTAssertEqual(format(.value(1_234.6)), "1,235")
        XCTAssertEqual(format(.value(1_234.6), locale: Locale(identifier: "de_DE")), "1.235")
        XCTAssertEqual(format(.value(1_234.6), locale: Locale(identifier: "ja_JP")), "1,235")
    }

    /// 未取得と、有限でない値(NaN・無限大)は未取得として `nil` を返します。
    ///
    /// 責務: 4通りの `nil` を確認します。
    func testUnavailableAndNonFiniteReturnNil() {
        XCTAssertNil(format(.unavailable))
        XCTAssertNil(format(.value(.nan)))
        XCTAssertNil(format(.value(.infinity)))
        XCTAssertNil(format(.value(-.infinity)))
    }
}
