import Foundation
import XCTest
@testable import ProjectZD8

/// 走行ルートの要約(長さ・記録できた時間・割合)の文字列への整形を、ロケールを ja / en に固定して検証します。
///
/// ロケールで変わり得る文字列は、数字と単位の構成要素で比べます。
@MainActor
final class DrivingRouteSummaryFormatterTests: XCTestCase {
    /// 固定して確かめるロケールです。
    private let localeIdentifiers = ["ja_JP", "en_US"]

    /// 1 km 未満は m で整数、1 km 以上は km の小数1桁です。
    ///
    /// 責務: 999 m・1,000 m・12,345 m の境界と小数の桁を両方のロケールで確認します。
    func testLengthSwitchesFromMetersToKilometersAtOneKilometer() {
        for identifier in localeIdentifiers {
            let formatter = makeFormatter(identifier)

            let meters = formatter.text(for: summary(lengthMeters: 999)).lengthText
            XCTAssertTrue(meters.contains("999") && meters.contains("m") && !meters.contains("km"), "\(identifier): \(meters)")

            let oneKilometer = formatter.text(for: summary(lengthMeters: 1_000)).lengthText
            XCTAssertTrue(oneKilometer.contains("1.0") && oneKilometer.contains("km"), "\(identifier): \(oneKilometer)")

            let kilometers = formatter.text(for: summary(lengthMeters: 12_345)).lengthText
            XCTAssertTrue(kilometers.contains("12.3") && kilometers.contains("km"), "\(identifier): \(kilometers)")
        }
    }

    /// 記録できた時間は、履歴の時間の整形と同じ表記です。
    ///
    /// 責務: 1時間未満と1時間以上の時間が、注入した `ConnectionHistoryMeasurementFormatter` の表記になることを確認します。
    func testRecordedDurationUsesHistoryDurationText() {
        for identifier in localeIdentifiers {
            let measurement = makeMeasurement(identifier)
            let formatter = DrivingRouteSummaryFormatter(measurement: measurement, locale: Locale(identifier: identifier))

            for duration in [TimeInterval(125), 3_660] {
                let text = formatter.text(for: summary(recordedDuration: duration)).recordedDurationText
                XCTAssertEqual(text, measurement.durationText(duration), "\(identifier): \(duration)")
            }
        }
    }

    /// 割合は百分率の整数に丸めます。
    ///
    /// 責務: 0.456 が 46、0.454 が 45、0 と 1 が 0 と 100 の百分率になることを両方のロケールで確認します。
    func testCoverageIsRoundedToWholePercent() {
        let expectations: [(Double, String)] = [(0.456, "46"), (0.454, "45"), (0, "0"), (1, "100")]
        for identifier in localeIdentifiers {
            let formatter = makeFormatter(identifier)
            for (ratio, digits) in expectations {
                let text = formatter.text(for: summary(coverageRatio: ratio)).coverageText
                XCTAssertEqual(text.filter(\.isNumber), digits, "\(identifier): \(ratio) → \(text)")
                XCTAssertTrue(text.contains("%"), "\(identifier): \(text)")
            }
        }
    }

    /// 割合が無い(分母が0以下)なら "—" です。
    ///
    /// 責務: `coverageRatio` が nil の時の文字列を両方のロケールで確認します。
    func testMissingCoverageIsDash() {
        XCTAssertEqual(DrivingRouteSummaryFormatter.unavailableCoverageText, "—")
        for identifier in localeIdentifiers {
            XCTAssertEqual(makeFormatter(identifier).text(for: summary(coverageRatio: nil)).coverageText, "—", identifier)
        }
    }

    /// ロケールを固定した整形器を作ります。
    ///
    /// 責務: 時間・距離の整形と割合の整形に同じロケールを渡します。
    /// - Parameter identifier: ロケールの識別子。
    /// - Returns: 整形器。
    private func makeFormatter(_ identifier: String) -> DrivingRouteSummaryFormatter {
        DrivingRouteSummaryFormatter(measurement: makeMeasurement(identifier), locale: Locale(identifier: identifier))
    }

    /// ロケールを固定した履歴の時間・距離の整形器を作ります。
    ///
    /// 責務: グレゴリオ暦の暦とロケールを指定の識別子に揃えます。
    /// - Parameter identifier: ロケールの識別子。
    /// - Returns: 時間・距離の整形器。
    private func makeMeasurement(_ identifier: String) -> ConnectionHistoryMeasurementFormatter {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: identifier)
        return ConnectionHistoryMeasurementFormatter(calendar: calendar, locale: Locale(identifier: identifier))
    }

    /// 要約を作ります。
    ///
    /// 責務: 確かめない項目を固定値にした要約を返します。
    /// - Parameters:
    ///   - lengthMeters: 長さ。
    ///   - recordedDuration: 記録できた時間。
    ///   - coverageRatio: 記録できた割合。
    /// - Returns: 要約。
    private func summary(
        lengthMeters: Double = 500,
        recordedDuration: TimeInterval = 60,
        coverageRatio: Double? = 0.5
    ) -> DrivingRouteSummary {
        DrivingRouteSummary(lengthMeters: lengthMeters, recordedDuration: recordedDuration, coverageRatio: coverageRatio)
    }
}
