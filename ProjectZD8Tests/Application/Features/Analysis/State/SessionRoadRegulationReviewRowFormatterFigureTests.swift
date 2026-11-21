import Foundation
import XCTest
@testable import ProjectZD8

/// 一覧の行の数値の文字列(`figureTexts`)の規則を検証します(設計書 §3.4 FigureTexts、§7 TC1a)。
///
/// 書式のキーは `キー=%@` に解決させ、`String(format:)` に渡る値の文字列(数値と単位)をそのまま確かめます。
@MainActor
final class SessionRoadRegulationReviewRowFormatterFigureTests: XCTestCase {
    /// 書式のキーの接頭辞です。
    private let prefix = "analysis.road_regulation.figure."

    /// ロケールを固定した formatter を作ります。
    ///
    /// 責務: 書式のキーを `キー=%@` に解決する検証対象を返します。
    /// - Parameter locale: ロケール識別子。
    /// - Returns: formatter。
    private func formatter(_ locale: String = "en_US_POSIX") -> SessionRoadRegulationReviewRowFormatter {
        SessionRoadRegulationReviewRowFormatter(
            locale: Locale(identifier: locale),
            timeZone: SessionRoadRegulationReviewTestValues.tokyo,
            localize: { "\($0)=%@" }
        )
    }

    /// 書式のキーと値の文字列から期待値を作ります。
    ///
    /// 責務: `接頭辞 + 名前=値` の形の期待値を返します。
    /// - Parameters:
    ///   - name: キーの末尾(limit など)。
    ///   - value: 値の文字列。
    /// - Returns: 期待値。
    private func figure(_ name: String, _ value: String) -> String {
        "\(prefix)\(name)=\(value)"
    }

    /// すべての項目に値を入れた数値です。
    ///
    /// 責務: 種類ごとに使わない項目を無視することを確かめる入力を返します。
    /// - Returns: 6項目すべてが非 nil の数値。
    private func allFigures() -> SessionRoadRegulationReviewFigures {
        SessionRoadRegulationReviewFigures(
            limitKph: 40,
            maximumKph: 52.26,
            minimumKph: 3.04,
            exceededSeconds: 6.0,
            wrongWayDistanceMeters: 120.6,
            referenceKph: 10
        )
    }

    /// 責務: 最高速度は 制限 → 最高 → 超過秒 の順で、最高は小数1桁(52.26 → 52.3)、超過秒は数値だけ(6.0 → 6)、
    /// 一時停止・一方通行・徐行の項目は値があっても出さないことを確かめます。
    func testSpeedLimitOrderAndIgnoredFigures() {
        let texts = formatter().figureTexts(allFigures(), kind: .speedLimit)

        XCTAssertEqual(texts, [figure("limit", "40 km/h"), figure("maximum", "52.3 km/h"), figure("exceeded_duration", "6")])
    }

    /// 責務: 最高速度で、nil の項目(最高)を飛ばし、整数の速度は小数を付けない(52.0 → 52)ことを確かめます。
    func testSpeedLimitSkipsNilAndDropsZeroFraction() {
        let withoutMaximum = SessionRoadRegulationReviewFigures(limitKph: 40, exceededSeconds: 6.04)
        let withoutLimit = SessionRoadRegulationReviewFigures(maximumKph: 52.0)

        XCTAssertEqual(formatter().figureTexts(withoutMaximum, kind: .speedLimit), [figure("limit", "40 km/h"), figure("exceeded_duration", "6")])
        XCTAssertEqual(formatter().figureTexts(withoutLimit, kind: .speedLimit), [figure("maximum", "52 km/h")])
    }

    /// 責務: 一時停止は最低速度だけを出し(3.04 → 3)、制限・最高などは無視することを確かめます。
    func testStopShowsMinimumOnly() {
        XCTAssertEqual(formatter().figureTexts(allFigures(), kind: .stop), [figure("minimum", "3 km/h")])
    }

    /// 責務: 一方通行は逆方向の距離だけを小数0桁で出し(120.6 → 121 m)、他の項目は無視することを確かめます。
    func testOneWayShowsDistanceOnlyRounded() {
        XCTAssertEqual(formatter().figureTexts(allFigures(), kind: .oneWay), [figure("wrong_way_distance", "121 m")])
    }

    /// 責務: 徐行は 最高 → 目安 の順で出し、制限・最低・超過秒・距離は無視することを確かめます。
    func testSlowDownOrderAndIgnoredFigures() {
        XCTAssertEqual(formatter().figureTexts(allFigures(), kind: .slowDown), [figure("maximum", "52.3 km/h"), figure("reference", "10 km/h")])
    }

    /// 責務: 徐行で最高が nil なら目安だけを出すことを確かめます。
    func testSlowDownSkipsNilMaximum() {
        let figures = SessionRoadRegulationReviewFigures(referenceKph: 10)

        XCTAssertEqual(formatter().figureTexts(figures, kind: .slowDown), [figure("reference", "10 km/h")])
    }

    /// 責務: 全項目が nil なら、4種類とも空の配列を返すことを確かめます。
    func testAllNilGivesEmptyForEveryKind() {
        for kind in SessionRoadRegulationReviewKind.allCases {
            XCTAssertEqual(formatter().figureTexts(.init(), kind: kind), [], "\(kind)")
        }
    }

    /// 責務: NaN と +∞ の項目は出さず、有限の項目だけを残すことを確かめます。
    func testNonFiniteValuesAreSkipped() {
        let speed = SessionRoadRegulationReviewFigures(limitKph: 40, maximumKph: .nan, exceededSeconds: .infinity)
        let stop = SessionRoadRegulationReviewFigures(minimumKph: .nan)
        let oneWay = SessionRoadRegulationReviewFigures(wrongWayDistanceMeters: -.infinity)
        let slowDown = SessionRoadRegulationReviewFigures(maximumKph: .infinity, referenceKph: 10)

        XCTAssertEqual(formatter().figureTexts(speed, kind: .speedLimit), [figure("limit", "40 km/h")])
        XCTAssertEqual(formatter().figureTexts(stop, kind: .stop), [])
        XCTAssertEqual(formatter().figureTexts(oneWay, kind: .oneWay), [])
        XCTAssertEqual(formatter().figureTexts(slowDown, kind: .slowDown), [figure("reference", "10 km/h")])
    }

    /// 責務: 小数点が「,」のロケール(de_DE)では、速度と秒の小数点に「,」を使う(52.5 → 52,5、2.26 → 2,3)ことを確かめます。
    func testCommaDecimalLocale() {
        let figures = SessionRoadRegulationReviewFigures(limitKph: 40, maximumKph: 52.5, exceededSeconds: 2.26)

        XCTAssertEqual(
            formatter("de_DE").figureTexts(figures, kind: .speedLimit),
            [figure("limit", "40 km/h"), figure("maximum", "52,5 km/h"), figure("exceeded_duration", "2,3")]
        )
    }

    /// 責務: ja_JP では距離に桁区切りを付け(1234.4 → 1,234 m)、速度は小数1桁で出すことを確かめます。
    func testJapaneseLocaleGroupingAndFraction() {
        let oneWay = SessionRoadRegulationReviewFigures(wrongWayDistanceMeters: 1_234.4)
        let stop = SessionRoadRegulationReviewFigures(minimumKph: 7.26)

        XCTAssertEqual(formatter("ja_JP").figureTexts(oneWay, kind: .oneWay), [figure("wrong_way_distance", "1,234 m")])
        XCTAssertEqual(formatter("ja_JP").figureTexts(stop, kind: .stop), [figure("minimum", "7.3 km/h")])
    }
}
