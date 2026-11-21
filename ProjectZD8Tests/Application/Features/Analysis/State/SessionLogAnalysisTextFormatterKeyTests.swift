import Foundation
import XCTest
@testable import ProjectZD8

/// 解析画面のローカライズキーとシンボルの選択(部品・相関・系列名)を検証します。
@MainActor
final class SessionLogAnalysisTextFormatterKeyTests: XCTestCase {
    /// 検証対象の解析画面向け整形です。
    private let formatter = SessionLogAnalysisTextFormatter()

    /// 部品・系統の見出しキーです。
    ///
    /// 責務: 5分類の見出しキーを確認します。
    func testComponentTitleKeys() {
        let expected: [(SessionComponentInsight.Component, String)] = [
            (.electrical, "analysis.components.electrical.title"),
            (.thermal, "analysis.components.thermal.title"),
            (.fuelAndIntake, "analysis.components.fuel_intake.title"),
            (.exhaust, "analysis.components.exhaust.title"),
            (.diagnostics, "analysis.components.diagnostics.title")
        ]
        for (component, key) in expected {
            XCTAssertEqual(formatter.componentTitleKey(component), key)
        }
    }

    /// 部品・系統の説明キーです。
    ///
    /// 責務: 5分類の説明キーを確認します。
    func testComponentDescriptionKeys() {
        let expected: [(SessionComponentInsight.Component, String)] = [
            (.electrical, "analysis.components.electrical.body"),
            (.thermal, "analysis.components.thermal.body"),
            (.fuelAndIntake, "analysis.components.fuel_intake.body"),
            (.exhaust, "analysis.components.exhaust.body"),
            (.diagnostics, "analysis.components.diagnostics.body")
        ]
        for (component, key) in expected {
            XCTAssertEqual(formatter.componentDescriptionKey(component), key)
        }
    }

    /// 部品・系統のSF Symbol名です。
    ///
    /// 責務: 5分類のシンボル名を確認します。
    func testComponentSymbols() {
        let expected: [(SessionComponentInsight.Component, String)] = [
            (.electrical, "bolt.12"),
            (.thermal, "thermometer.medium"),
            (.fuelAndIntake, "wind"),
            (.exhaust, "aqi.medium"),
            (.diagnostics, "wrench.and.screwdriver")
        ]
        for (component, symbol) in expected {
            XCTAssertEqual(formatter.componentSymbol(component), symbol)
        }
    }

    /// 既定の6組は、それぞれ専用の案内キーです。
    ///
    /// 責務: 横軸・縦軸のService/PIDの組ごとの案内キーを確認します。
    func testRelationshipGuideKeysForKnownPairs() {
        let cases: [((UInt8, UInt8), (UInt8, UInt8), String)] = [
            ((0x01, 0x0C), (0x01, 0x0D), "analysis.relationship.guide.rpm_speed"),
            ((0x01, 0x0C), (0x01, 0x04), "analysis.relationship.guide.rpm_load"),
            ((0x01, 0x0C), (0x01, 0x10), "analysis.relationship.guide.rpm_maf"),
            ((0x01, 0x11), (0x01, 0x04), "analysis.relationship.guide.throttle_load"),
            ((0x01, 0x06), (0x01, 0x07), "analysis.relationship.guide.trim_banks"),
            ((0x01, 0x0D), (0x21, 0x17), "analysis.relationship.guide.speed_zd8_atf")
        ]
        for (x, y, key) in cases {
            let relationship = TestSessionLogAnalysisFixtures.makeRelationship(x: x, y: y)

            XCTAssertEqual(formatter.relationshipGuideKey(relationship), key)
        }
    }

    /// 既定以外の組は共通の案内キーです。
    ///
    /// 責務: 軸の入れ替え、Serviceだけ違う組、無関係な組が共通キーになることを確認します。
    func testRelationshipGuideKeyFallsBackToCommon() {
        let cases: [((UInt8, UInt8), (UInt8, UInt8))] = [
            ((0x01, 0x0D), (0x01, 0x0C)),
            ((0x21, 0x0C), (0x01, 0x0D)),
            ((0x01, 0x0C), (0x21, 0x0D)),
            ((0x01, 0x05), (0x01, 0x5C))
        ]
        for (x, y) in cases {
            let relationship = TestSessionLogAnalysisFixtures.makeRelationship(x: x, y: y)

            XCTAssertEqual(formatter.relationshipGuideKey(relationship), "analysis.relationship.guide.common")
        }
    }

    /// 名称キーがあれば、その文言を系列名にします。
    ///
    /// 責務: PID定義の名称キーが解決された文言になることを確認します。
    func testSeriesNameUsesLocalizedNameKey() {
        let series = TestSessionLogAnalysisFixtures.makeSeries(service: 0x01, pid: 0x0C, nameKey: "obd.pid.01.0C.name")

        XCTAssertEqual(formatter.seriesName(series), String(localized: "obd.pid.01.0C.name"))
        XCTAssertNotEqual(formatter.seriesName(series), "obd.pid.01.0C.name")
    }

    /// 名称キーが無ければ、Service/PID識別子を系列名にします。
    ///
    /// 責務: 代替表示が `pidLabel` と一致することを確認します。
    func testSeriesNameFallsBackToPIDLabel() {
        let series = TestSessionLogAnalysisFixtures.makeSeries(service: 0x21, pid: 0x2A)

        XCTAssertEqual(formatter.seriesName(series), formatter.pidLabel(service: 0x21, pid: 0x2A))
    }

    /// 相関の名前は2系列名を ` × ` で結びます。
    ///
    /// 責務: 横軸名と縦軸名の順序と区切りを確認します。
    func testRelationshipNameJoinsAxisNames() {
        let relationship = TestSessionLogAnalysisFixtures.makeRelationship(x: (0x01, 0x0C), y: (0x01, 0x0D))
        let x = formatter.seriesName(relationship.xSeries)
        let y = formatter.seriesName(relationship.ySeries)

        XCTAssertEqual(formatter.relationshipName(relationship), "\(x) × \(y)")
        XCTAssertNotEqual(x, y)
    }

    /// PID識別子は2桁の大文字16進で、ServiceとPIDの両方を含みます。
    ///
    /// 責務: ゼロ埋めと大文字の16進表記を確認します。
    func testPIDLabelUsesTwoDigitUppercaseHex() {
        let label = formatter.pidLabel(service: 0x01, pid: 0x0A)

        XCTAssertTrue(label.contains("01"))
        XCTAssertTrue(label.contains("0A"))
        XCTAssertTrue(formatter.pidLabel(service: 0xAB, pid: 0xCD).contains("AB"))
        XCTAssertTrue(formatter.pidLabel(service: 0xAB, pid: 0xCD).contains("CD"))
    }
}
