import Foundation
import XCTest
@testable import ProjectZD8

/// 指標の色分けの凡例(5区分の範囲の数値と単位、必要な時だけ値なし)を作る規則を検証します(設計書 §2.4、§6)。
///
/// 文言の言い回しは翻訳で変わるため、ロケールを固定し、項目ごとの数字の並びと単位で確かめます。
@MainActor
final class RouteAnalysisLegendBuilderTests: XCTestCase {
    /// ロケールを固定した検証対象です。
    private let builder = RouteAnalysisLegendBuilder(locale: Locale(identifier: "en_US"))
    /// 5区分の分類(区分の順)です。
    private let rampCategories: [RouteAnalysisColorCategory] = (0..<5).map { .ramp(step: $0) }

    /// 文字列の数字だけを取り出します。
    ///
    /// 責務: 桁区切りや記号に左右されずに、表示された数値を比べられるようにします。
    /// - Parameter text: 文字列。
    /// - Returns: 数字だけの文字列。
    private func digits(_ text: String) -> String {
        String(text.filter(\.isNumber))
    }

    /// 区分の項目の数字の並びを返します。
    ///
    /// 責務: 値なしを除いた項目を区分の順に取り出し、数字だけにします。
    /// - Parameter entries: 凡例。
    /// - Returns: 区分ごとの数字の並び。
    private func rampDigits(_ entries: [RouteAnalysisLegendEntry]) -> [String] {
        entries.filter { $0.category != .noValue }.map { digits($0.text) }
    }

    /// 責務: 車速の凡例が、区分0〜4の順に「20 未満 / 20〜40 / 40〜60 / 60〜80 / 80 以上」の数値を持つことを確かめます。
    func testVehicleSpeedLegend() {
        let entries = builder.legend(metric: .vehicleSpeed, unit: "km/h", includesNoValue: false)

        XCTAssertEqual(entries.map(\.category), rampCategories)
        XCTAssertEqual(rampDigits(entries), ["20", "2040", "4060", "6080", "80"])
    }

    /// 責務: エンジン回転の凡例が、1500 / 2500 / 3500 / 4500 の境界で区切られ、数値がロケールの桁区切り(en_US の「1,500」)で整形されることを確かめます。
    func testEngineSpeedLegend() {
        let entries = builder.legend(metric: .engineSpeed, unit: "rpm", includesNoValue: false)

        XCTAssertEqual(entries.map(\.category), rampCategories)
        XCTAssertEqual(rampDigits(entries), ["1500", "15002500", "25003500", "35004500", "4500"])
        XCTAssertTrue(entries[0].text.contains("1,500"), entries[0].text)
        XCTAssertTrue(entries[4].text.contains("4,500"), entries[4].text)
    }

    /// 責務: エンジン負荷の凡例が、20 / 40 / 60 / 80 の境界で区切られることを確かめます。
    func testEngineLoadLegend() {
        let entries = builder.legend(metric: .engineLoad, unit: "%", includesNoValue: false)

        XCTAssertEqual(entries.map(\.category), rampCategories)
        XCTAssertEqual(rampDigits(entries), ["20", "2040", "4060", "6080", "80"])
    }

    /// 責務: 水温の凡例が、60 / 80 / 95 / 105 の境界で区切られることを確かめます。
    func testCoolantTemperatureLegend() {
        let entries = builder.legend(metric: .coolantTemperature, unit: "°C", includesNoValue: false)

        XCTAssertEqual(entries.map(\.category), rampCategories)
        XCTAssertEqual(rampDigits(entries), ["60", "6080", "8095", "95105", "105"])
    }

    /// 責務: 区分の各項目に、渡した単位が入ることを確かめます(指標の既定の単位ではなく引数の単位)。
    func testEntriesIncludeGivenUnit() {
        let entries = builder.legend(metric: .vehicleSpeed, unit: "mph", includesNoValue: false)

        XCTAssertEqual(entries.count, 5)
        XCTAssertTrue(entries.allSatisfy { $0.text.contains("mph") }, "\(entries.map(\.text))")
    }

    /// 責務: 値なしの項目を求めなければ、値なしが含まれないことを確かめます。
    func testNoValueEntryOmittedWhenNotRequested() {
        let entries = builder.legend(metric: .engineLoad, unit: "%", includesNoValue: false)

        XCTAssertFalse(entries.contains { $0.category == .noValue })
    }

    /// 責務: 値なしの項目を求めると、区分の5項目はそのままに値なしが1つだけ加わることを確かめます。
    func testNoValueEntryAddedWhenRequested() {
        let entries = builder.legend(metric: .vehicleSpeed, unit: "km/h", includesNoValue: true)

        XCTAssertEqual(entries.count, 6)
        XCTAssertEqual(entries.filter { $0.category == .noValue }.count, 1)
        XCTAssertEqual(entries.filter { $0.category != .noValue }.map(\.category), rampCategories)
        XCTAssertEqual(rampDigits(entries), ["20", "2040", "4060", "6080", "80"])
    }

    /// 責務: 区分の項目の ID が 0〜4、値なしの項目の ID が 5 であることを確かめます。
    func testEntryIDs() {
        let entries = builder.legend(metric: .coolantTemperature, unit: "°C", includesNoValue: true)

        XCTAssertEqual(entries.filter { $0.category != .noValue }.map(\.id), [0, 1, 2, 3, 4])
        XCTAssertEqual(entries.filter { $0.category == .noValue }.map(\.id), [5])
    }

    /// 責務: 単位が空白だけなら、指標の既定の単位を使うことを確かめます。
    func testBlankUnitFallsBackToMetricUnit() {
        let entries = builder.legend(metric: .engineSpeed, unit: "  ", includesNoValue: false)

        XCTAssertEqual(entries.count, 5)
        XCTAssertTrue(entries.allSatisfy { $0.text.contains("rpm") }, "\(entries.map(\.text))")
    }
}
