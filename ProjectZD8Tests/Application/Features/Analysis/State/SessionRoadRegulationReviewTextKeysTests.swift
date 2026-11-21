import Foundation
import XCTest
@testable import ProjectZD8

/// 交通規制の照合の表示で使うキー・記号・色の分類の表引きを検証します(設計書 §3.3 の2つの表)。
///
/// 期待値は設計書の表を手で写した文字列で書き、製品の表引きを期待値に使いません。
@MainActor
final class SessionRoadRegulationReviewTextKeysTests: XCTestCase {
    /// 検証対象です。
    private let keys = SessionRoadRegulationReviewTextKeys()
    /// 組み合わせの無い時に返す、判定できない旨のキーです。
    private let undetermined = "analysis.road_regulation.outcome.undetermined"

    /// 種類ごとに、結果の allCases の順のラベルのキーを返します。
    ///
    /// 責務: 1種類について5つの結果のラベルを並べ、表と比べられる形にします。
    /// - Parameter kind: 種類。
    /// - Returns: possibleIssue / undeterminable / compliant / observedOnly / unregulated の順のキー。
    private func labels(for kind: SessionRoadRegulationReviewKind) -> [String] {
        SessionRoadRegulationReviewOutcome.allCases.map { keys.outcomeLabelKey(kind: kind, outcome: $0) }
    }

    /// 責務: 最高速度のラベルが、超過・判定できない・制限内・(無し)・指定なしの順に表どおりであることを確かめます。
    func testSpeedLimitOutcomeLabels() {
        let expected: [String] = [
            "road_regulation.verdict.speed_limit.exceeded",
            undetermined,
            "road_regulation.verdict.speed_limit.within_limit",
            undetermined,
            "road_regulation.verdict.speed_limit.unregulated"
        ]

        XCTAssertEqual(labels(for: .speedLimit), expected)
    }

    /// 責務: 一時停止のラベルが表どおりで、徐行の通過・指定なしの組み合わせは判定できない旨のキーに倒れることを確かめます。
    func testStopOutcomeLabels() {
        let expected: [String] = [
            "road_regulation.verdict.stop.not_stopped",
            undetermined,
            "road_regulation.verdict.stop.stopped",
            undetermined,
            undetermined
        ]

        XCTAssertEqual(labels(for: .stop), expected)
    }

    /// 責務: 一方通行のラベルが表どおりで、無い組み合わせは判定できない旨のキーに倒れることを確かめます。
    func testOneWayOutcomeLabels() {
        let expected: [String] = [
            "road_regulation.verdict.one_way.possible_wrong_way",
            undetermined,
            "road_regulation.verdict.one_way.followed_direction",
            undetermined,
            undetermined
        ]

        XCTAssertEqual(labels(for: .oneWay), expected)
    }

    /// 責務: 徐行のラベルが、通過だけ `slow_down.observed` で、超過・制限内・指定なしは判定できない旨のキーに倒れることを確かめます。
    func testSlowDownOutcomeLabels() {
        let expected: [String] = [
            undetermined,
            undetermined,
            undetermined,
            "road_regulation.verdict.slow_down.observed",
            undetermined
        ]

        XCTAssertEqual(labels(for: .slowDown), expected)
    }

    /// 責務: 結果ごとの色の分類が表どおり(注意・不明・良好・中立・中立)であることを確かめます。
    func testCategoryForEachOutcome() {
        let categories: [RouteAnalysisColorCategory] = SessionRoadRegulationReviewOutcome.allCases.map { keys.category(for: $0) }
        let expected: [RouteAnalysisColorCategory] = [
            .tone(.caution), .tone(.unknown), .tone(.positive), .tone(.neutral), .tone(.neutral)
        ]

        XCTAssertEqual(categories, expected)
    }

    /// 責務: 断定を避けるため、どの結果にも `.tone(.critical)` を返さないことを確かめます。
    func testNoOutcomeUsesCriticalTone() {
        for outcome in SessionRoadRegulationReviewOutcome.allCases {
            XCTAssertNotEqual(keys.category(for: outcome), .tone(.critical), "\(outcome)")
        }
    }

    /// 責務: 結果ごとの記号が表どおりであることを確かめます。
    func testSystemImageForEachOutcome() {
        let images: [String] = SessionRoadRegulationReviewOutcome.allCases.map { keys.systemImage(for: $0) }
        let expected: [String] = [
            "exclamationmark.triangle.fill",
            "questionmark.circle",
            "checkmark.circle",
            "gauge.with.dots.needle.33percent",
            "minus.circle"
        ]

        XCTAssertEqual(images, expected)
    }

    /// 責務: 種類名のキーが `road_regulation.kind.*` の4件であることを確かめます。
    func testKindTitleKeys() {
        let titles: [String] = SessionRoadRegulationReviewKind.allCases.map { keys.kindTitleKey(for: $0) }
        let expected: [String] = [
            "road_regulation.kind.speed_limit",
            "road_regulation.kind.stop",
            "road_regulation.kind.one_way",
            "road_regulation.kind.slow_down"
        ]

        XCTAssertEqual(titles, expected)
    }

    /// 責務: 重ね合わせの ID が `road_regulation.<snake>` の4件で、互いに異なることを確かめます。
    func testOverlayIDsAreDistinctSnakeCase() {
        let ids: [String] = SessionRoadRegulationReviewKind.allCases.map { keys.overlayID(for: $0) }
        let expected: [String] = [
            "road_regulation.speed_limit",
            "road_regulation.stop",
            "road_regulation.one_way",
            "road_regulation.slow_down"
        ]

        XCTAssertEqual(ids, expected)
        XCTAssertEqual(Set(ids).count, 4)
    }

    /// 責務: 重ね合わせの題名のキーが `analysis.road_regulation.overlay.<snake>` の4件であることを確かめます。
    func testOverlayTitleKeys() {
        let titles: [String] = SessionRoadRegulationReviewKind.allCases.map { keys.overlayTitleKey(for: $0) }
        let expected: [String] = [
            "analysis.road_regulation.overlay.speed_limit",
            "analysis.road_regulation.overlay.stop",
            "analysis.road_regulation.overlay.one_way",
            "analysis.road_regulation.overlay.slow_down"
        ]

        XCTAssertEqual(titles, expected)
    }

    /// 責務: 凡例の「該当する規制なし」と、一覧が空の時の2つのキーが設計書どおりであることを確かめます。
    func testFixedKeys() {
        XCTAssertEqual(keys.notApplicableLabelKey, "analysis.road_regulation.legend.not_applicable")
        XCTAssertEqual(keys.emptyKindKey, "analysis.road_regulation.list.empty_kind")
        XCTAssertEqual(keys.emptyFilteredKey, "analysis.road_regulation.list.empty_attention")
    }

    /// 責務: 状態の文言キーが9段階とも表どおりで、idle は waitingForRoute と同じキー、loaded は nil であることを確かめます。
    func testStatusMessageKeys() {
        let prefix = "analysis.road_regulation.status."
        let expected: [(SessionRoadRegulationReviewStatus, String?)] = [
            (.idle, prefix + "waiting_for_route"),
            (.waitingForRoute, prefix + "waiting_for_route"),
            (.routeUnavailable, prefix + "route_unavailable"),
            (.waitingForRawLog, prefix + "waiting_for_raw_log"),
            (.evaluating, prefix + "evaluating"),
            (.loaded, nil),
            (.noTrack, prefix + "no_track"),
            (.noRegulationData, prefix + "no_regulation_data"),
            (.failed, prefix + "failed")
        ]

        for (status, key) in expected {
            XCTAssertEqual(keys.statusMessageKey(for: status), key, "\(status)")
        }
    }

    /// 責務: 状態の記号が9段階とも表どおりで、進捗を出す段階(waitingForRawLog・evaluating)と loaded は nil であることを確かめます。
    func testStatusSystemImages() {
        let expected: [(SessionRoadRegulationReviewStatus, String?)] = [
            (.idle, "hourglass"),
            (.waitingForRoute, "hourglass"),
            (.routeUnavailable, "map"),
            (.waitingForRawLog, nil),
            (.evaluating, nil),
            (.loaded, nil),
            (.noTrack, "location.slash"),
            (.noRegulationData, "square.and.arrow.down"),
            (.failed, "exclamationmark.triangle.fill")
        ]

        for (status, image) in expected {
            XCTAssertEqual(keys.statusSystemImage(for: status), image, "\(status)")
        }
    }
}
