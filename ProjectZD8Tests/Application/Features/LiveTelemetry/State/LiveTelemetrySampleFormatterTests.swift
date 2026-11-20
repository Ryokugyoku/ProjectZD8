import XCTest
@testable import ProjectZD8

/// PID の値を、主要値は小数0〜1桁、詳細値は小数0〜2桁で、ロケールの小数点と桁区切りに従って整形する規則を検証します。
///
/// 期待値は各ロケールの規則(CLDR)から導いています。en_US と ja_JP は小数点 `.`・桁区切り `,`、
/// es_ES は小数点 `,`・桁区切り `.` で、整数部が4桁の時は桁区切りを入れません(最小グルーピング桁数 2)。
@MainActor
final class LiveTelemetrySampleFormatterTests: XCTestCase {
    private let formatter = LiveTelemetrySampleFormatter()
    private let enUS = Locale(identifier: "en_US")
    private let jaJP = Locale(identifier: "ja_JP")
    private let esES = Locale(identifier: "es_ES")

    /// 値だけを持つサンプルを作ります。
    ///
    /// 責務: 値と単位を指定した整形対象を返します。
    private func sample(_ value: Double, unit: String = "rpm") -> OBDPIDSample {
        LiveTelemetryPanelTestFixture.sample(pid: 0x0C, value: value, unit: unit)
    }

    /// 主要値は小数1桁に丸め、整数なら小数部を出さず、単位を付けません。
    ///
    /// 責務: en_US で主要値の丸めと小数0桁・1桁の境界を確かめます。
    func testPrimaryValueTextRoundsToOneFractionDigitInEnglish() {
        XCTAssertEqual(formatter.primaryValueText(sample(1234.56), locale: enUS), "1,234.6")
        XCTAssertEqual(formatter.primaryValueText(sample(1234), locale: enUS), "1,234")
        XCTAssertEqual(formatter.primaryValueText(sample(2.04), locale: enUS), "2")
        XCTAssertEqual(formatter.primaryValueText(sample(2.06), locale: enUS), "2.1")
        XCTAssertEqual(formatter.primaryValueText(sample(0), locale: enUS), "0")
        XCTAssertEqual(formatter.primaryValueText(sample(-40.26), locale: enUS), "-40.3")
    }

    /// 日本語のロケールも小数点 `.` と桁区切り `,` です。
    ///
    /// 責務: ja_JP で主要値の整形を確かめます。
    func testPrimaryValueTextInJapanese() {
        XCTAssertEqual(formatter.primaryValueText(sample(12345.67), locale: jaJP), "12,345.7")
        XCTAssertEqual(formatter.primaryValueText(sample(80), locale: jaJP), "80")
    }

    /// スペイン語のロケールは小数点 `,` で、5桁以上の整数部だけ `.` で区切ります。
    ///
    /// 責務: es_ES で主要値の小数点と桁区切りの境界を確かめます。
    func testPrimaryValueTextInSpanish() {
        XCTAssertEqual(formatter.primaryValueText(sample(1234.56), locale: esES), "1234,6")
        XCTAssertEqual(formatter.primaryValueText(sample(12345.67), locale: esES), "12.345,7")
        XCTAssertEqual(formatter.primaryValueText(sample(3), locale: esES), "3")
    }

    /// 詳細値は小数2桁に丸め、末尾の0は出しません。
    ///
    /// 責務: en_US で詳細値の丸めと小数0桁・1桁・2桁の境界を確かめます。
    func testDetailValueTextRoundsToTwoFractionDigitsInEnglish() {
        XCTAssertEqual(formatter.detailValueText(sample(1234.567), locale: enUS), "1,234.57")
        XCTAssertEqual(formatter.detailValueText(sample(1234.5), locale: enUS), "1,234.5")
        XCTAssertEqual(formatter.detailValueText(sample(3), locale: enUS), "3")
        XCTAssertEqual(formatter.detailValueText(sample(0.004), locale: enUS), "0")
        XCTAssertEqual(formatter.detailValueText(sample(0.006), locale: enUS), "0.01")
    }

    /// 日本語のロケールでも詳細値は小数2桁までです。
    ///
    /// 責務: ja_JP で詳細値の整形を確かめます。
    func testDetailValueTextInJapanese() {
        XCTAssertEqual(formatter.detailValueText(sample(12345.678), locale: jaJP), "12,345.68")
    }

    /// スペイン語のロケールの詳細値は小数点 `,` と桁区切り `.` です。
    ///
    /// 責務: es_ES で詳細値の整形を確かめます。
    func testDetailValueTextInSpanish() {
        XCTAssertEqual(formatter.detailValueText(sample(12345.678), locale: esES), "12.345,68")
        XCTAssertEqual(formatter.detailValueText(sample(1234.5), locale: esES), "1234,5")
    }

    /// 単位付きの詳細値は詳細値と単位を空白1つでつなぎます。
    ///
    /// 責務: 単位がある時の連結を3ロケールで確かめます。
    func testDetailValueWithUnitTextJoinsWithSpace() {
        XCTAssertEqual(formatter.detailValueWithUnitText(sample(1234.567, unit: "rpm"), locale: enUS), "1,234.57 rpm")
        XCTAssertEqual(formatter.detailValueWithUnitText(sample(12345.678, unit: "km/h"), locale: jaJP), "12,345.68 km/h")
        XCTAssertEqual(formatter.detailValueWithUnitText(sample(12345.678, unit: "km/h"), locale: esES), "12.345,68 km/h")
    }

    /// 単位が空なら空白を付けず、詳細値だけにします。
    ///
    /// 責務: 単位が空の分岐を確かめます。
    func testDetailValueWithUnitTextWithoutUnit() {
        XCTAssertEqual(formatter.detailValueWithUnitText(sample(1234.567, unit: ""), locale: enUS), "1,234.57")
        XCTAssertEqual(formatter.detailValueWithUnitText(sample(1234.5, unit: ""), locale: esES), "1234,5")
    }
}
