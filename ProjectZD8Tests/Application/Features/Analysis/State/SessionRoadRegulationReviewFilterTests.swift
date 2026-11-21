import Foundation
import XCTest
@testable import ProjectZD8

/// 一覧の絞り込み(確認が必要な区間 / すべて)の計算を検証します(設計書 §3.2 Filter、§7 TC1b)。
@MainActor
final class SessionRoadRegulationReviewFilterTests: XCTestCase {
    /// 責務: 「確認が必要な区間」は possibleIssue と undeterminable だけを含め、他の3つを含めないことを5つの結果すべてで確かめます。
    func testAttentionIncludesOnlyIssueAndUndeterminable() {
        let expected: [(SessionRoadRegulationReviewOutcome, Bool)] = [
            (.possibleIssue, true),
            (.undeterminable, true),
            (.compliant, false),
            (.observedOnly, false),
            (.unregulated, false)
        ]

        for (outcome, included) in expected {
            XCTAssertEqual(SessionRoadRegulationReviewFilter.attention.includes(outcome), included, "\(outcome)")
        }
    }

    /// 責務: 「すべて」は5つの結果をすべて含めることを確かめます。
    func testAllIncludesEveryOutcome() {
        for outcome in SessionRoadRegulationReviewOutcome.allCases {
            XCTAssertTrue(SessionRoadRegulationReviewFilter.all.includes(outcome), "\(outcome)")
        }
    }

    /// 責務: 題名のキーが2件とも設計書どおりであることを確かめます。
    func testTitleKeys() {
        XCTAssertEqual(SessionRoadRegulationReviewFilter.attention.titleKey, "analysis.road_regulation.filter.attention")
        XCTAssertEqual(SessionRoadRegulationReviewFilter.all.titleKey, "analysis.road_regulation.filter.all")
    }

    /// 責務: id が rawValue で互いに異なり、選択肢の並びが attention → all であることを確かめます。
    func testIdentifiersAndOrder() {
        XCTAssertEqual(SessionRoadRegulationReviewFilter.allCases, [.attention, .all])
        XCTAssertEqual(SessionRoadRegulationReviewFilter.attention.id, "attention")
        XCTAssertEqual(SessionRoadRegulationReviewFilter.all.id, "all")
    }
}
