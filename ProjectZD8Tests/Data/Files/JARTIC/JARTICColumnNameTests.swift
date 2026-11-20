import Foundation
import XCTest
@testable import ProjectZD8

/// `JARTICColumnName` の名前の組み立て(条件の組・項目の別)を検証します。
@MainActor
final class JARTICColumnNameTests: XCTestCase {
    /// 期間の開始の名前は、設計書の例どおりです。
    func testPeriodStartNamesMatchDesignExamples() {
        XCTAssertEqual(JARTICColumnName.target(1, .periodStart), "対象期間1_開始")
        XCTAssertEqual(JARTICColumnName.exclusion(1, .periodStart), "除外期間1_開始")
    }

    /// 組の番号と項目の別ごとに、名前が全て異なります(5組 × 9項目 × 対象・除外 = 90個)。
    func testConditionNamesAreDistinct() {
        let names = (1...5).flatMap { set in
            JARTICConditionField.allCases.flatMap { [JARTICColumnName.target(set, $0), JARTICColumnName.exclusion(set, $0)] }
        }
        XCTAssertEqual(names.count, 90)
        XCTAssertEqual(Set(names).count, 90)
    }

    /// 必須の列は、固定の13個と、条件の90個を全て含みます。
    func testRequiredContainsFixedAndConditionNames() {
        let fixed = [
            JARTICColumnName.formatVersion, JARTICColumnName.kindCode, JARTICColumnName.shapeCode,
            JARTICColumnName.abolishedOn, JARTICColumnName.updateKind, JARTICColumnName.uniqueKey,
            JARTICColumnName.coordinates, JARTICColumnName.exclusionCoordinates, JARTICColumnName.perimeterRoad,
            JARTICColumnName.approachCoordinates, JARTICColumnName.oneWayOrder, JARTICColumnName.side,
            JARTICColumnName.speed
        ]
        let conditions = (1...5).flatMap { set in
            JARTICConditionField.allCases.flatMap { [JARTICColumnName.target(set, $0), JARTICColumnName.exclusion(set, $0)] }
        }
        XCTAssertEqual(Set(JARTICColumnName.required), Set(fixed + conditions))
    }

    /// 固定の列の名前は、実データの見出しの文字列(半角括弧)どおりです。
    func testFixedNamesMatchSpecWording() {
        XCTAssertEqual(JARTICColumnName.formatVersion, "拡張版標準フォーマット種別・バージョン")
        XCTAssertEqual(JARTICColumnName.approachCoordinates, "進入方向(座標)")
        XCTAssertEqual(JARTICColumnName.uniqueKey, "ユニークキー")
    }
}
