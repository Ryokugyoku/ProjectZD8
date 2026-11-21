import Foundation
import XCTest
@testable import ProjectZD8

/// 規制の判定の文言キー(`RoadRegulationVerdictTextKeys`)が返すすべてのキーが、ja / en / es で訳されていることを検証します。
@MainActor
final class RoadRegulationVerdictLocalizationTests: XCTestCase {
    private let textKeys = RoadRegulationVerdictTextKeys()
    private let reason = RoadRegulationUndeterminedReason.coarseGeometry

    /// 責務: 最高速度の判定を全 case 並べ、case が増えたらコンパイルエラーにします(`switch` に `default` を置かない)。
    private func speedVerdicts() -> [SpeedLimitVerdict] {
        let verdicts: [SpeedLimitVerdict] = [
            .withinLimit(maxKph: 40), .exceeded(maxKph: 40, exceededSeconds: 3), .unregulated, .undeterminable(reason)
        ]
        for verdict in verdicts {
            switch verdict {
            case .withinLimit, .exceeded, .unregulated, .undeterminable: break
            }
        }
        return verdicts
    }

    /// 責務: 一時停止の判定を全 case 並べ、case が増えたらコンパイルエラーにします。
    private func stopVerdicts() -> [StopVerdict] {
        let verdicts: [StopVerdict] = [.stopped, .notStopped(minimumKph: 5), .undeterminable(reason)]
        for verdict in verdicts {
            switch verdict {
            case .stopped, .notStopped, .undeterminable: break
            }
        }
        return verdicts
    }

    /// 責務: 一方通行の判定を全 case 並べ、case が増えたらコンパイルエラーにします。
    private func oneWayVerdicts() -> [OneWayVerdict] {
        let verdicts: [OneWayVerdict] = [.followedDirection, .possibleWrongWay(distanceMeters: 10), .undeterminable(reason)]
        for verdict in verdicts {
            switch verdict {
            case .followedDirection, .possibleWrongWay, .undeterminable: break
            }
        }
        return verdicts
    }

    /// 責務: 徐行の判定を全 case 並べ、case が増えたらコンパイルエラーにします。
    private func slowDownVerdicts() -> [SlowDownVerdict] {
        let verdicts: [SlowDownVerdict] = [.observed(maxKph: 8, referenceKph: 10), .undeterminable(reason)]
        for verdict in verdicts {
            switch verdict {
            case .observed, .undeterminable: break
            }
        }
        return verdicts
    }

    /// 責務: 判定・理由・種類のすべてのキーを集めます(理由は全 case を直接も渡す)。
    private func allKeys() -> [String] {
        let verdictKeys: [String] = speedVerdicts().map { textKeys.key(for: $0) }
            + stopVerdicts().map { textKeys.key(for: $0) }
            + oneWayVerdicts().map { textKeys.key(for: $0) }
            + slowDownVerdicts().map { textKeys.key(for: $0) }
        let reasonKeys: [String] = RoadRegulationUndeterminedReason.allCases.map { textKeys.key(for: $0) }
        let kindKeys: [String] = RoadRegulationKind.allCases.map { textKeys.kindKey(for: $0) }
        return verdictKeys + reasonKeys + kindKeys
    }

    /// 判定・理由・種類のすべてのキーが、ja / en / es とも空でない訳を持ち、書式指定子が揃い、ja のままではありません。
    ///
    /// 責務: 全 case のキーをカタログと突き合わせます。
    func testEveryVerdictReasonAndKindKeyIsTranslatedInAllLanguages() throws {
        let checker = try LocalizableCatalogChecker()
        let keys = Array(Set(allKeys())).sorted()

        XCTAssertGreaterThanOrEqual(keys.count, 25, "キーが集まっていない")
        checker.assertAll(keys)
    }

    /// 判定できない理由の全 case について、キーが仕様どおりの名前で、カタログにあります。
    ///
    /// 責務: キーの綴りを実装の出力でなく、仕様の一覧(snake_case)と比べます。
    func testUndeterminedReasonKeysMatchSpecifiedNamesAndExistInCatalog() throws {
        let checker = try LocalizableCatalogChecker()
        let expected: [RoadRegulationUndeterminedReason: String] = [
            .coarseGeometry: "coarse_geometry", .ambiguousCandidates: "ambiguous_candidates",
            .conditionUnknown: "condition_unknown", .variableSpeedLimit: "variable_speed_limit",
            .oneSidedSection: "one_sided_section", .nearZoneBoundary: "near_zone_boundary",
            .nearExclusionArea: "near_exclusion_area", .headingUnknown: "heading_unknown",
            .outsideRegulationData: "outside_regulation_data", .speedUnavailable: "speed_unavailable",
            .speedSamplingTooSparse: "speed_sampling_too_sparse", .possiblyDifferentRoad: "possibly_different_road",
            .insufficientDistance: "insufficient_distance", .lowAccuracy: "low_accuracy", .trackGap: "track_gap"
        ]

        XCTAssertEqual(expected.count, RoadRegulationUndeterminedReason.allCases.count)
        for reason in RoadRegulationUndeterminedReason.allCases {
            let key = textKeys.key(for: reason)
            XCTAssertEqual(key, "road_regulation.undetermined.\(expected[reason] ?? "<missing>")")
            checker.assertTranslated([key])
        }
    }

    /// 判定のキーと種類のキーが、仕様どおりの名前です。
    ///
    /// 責務: 判定(理由なし)と種類の綴りを固定の一覧と比べます。
    func testVerdictAndKindKeysMatchSpecifiedNames() {
        XCTAssertEqual(textKeys.key(for: SpeedLimitVerdict.withinLimit(maxKph: 40)), "road_regulation.verdict.speed_limit.within_limit")
        XCTAssertEqual(textKeys.key(for: SpeedLimitVerdict.exceeded(maxKph: 40, exceededSeconds: 1)), "road_regulation.verdict.speed_limit.exceeded")
        XCTAssertEqual(textKeys.key(for: SpeedLimitVerdict.unregulated), "road_regulation.verdict.speed_limit.unregulated")
        XCTAssertEqual(textKeys.key(for: StopVerdict.stopped), "road_regulation.verdict.stop.stopped")
        XCTAssertEqual(textKeys.key(for: StopVerdict.notStopped(minimumKph: 5)), "road_regulation.verdict.stop.not_stopped")
        XCTAssertEqual(textKeys.key(for: OneWayVerdict.followedDirection), "road_regulation.verdict.one_way.followed_direction")
        XCTAssertEqual(textKeys.key(for: OneWayVerdict.possibleWrongWay(distanceMeters: 1)), "road_regulation.verdict.one_way.possible_wrong_way")
        XCTAssertEqual(textKeys.key(for: SlowDownVerdict.observed(maxKph: 8, referenceKph: 10)), "road_regulation.verdict.slow_down.observed")
        XCTAssertEqual(textKeys.kindKey(for: .speedLimitSection), "road_regulation.kind.speed_limit")
        XCTAssertEqual(textKeys.kindKey(for: .speedLimitVariableSection), "road_regulation.kind.speed_limit")
        XCTAssertEqual(textKeys.kindKey(for: .speedLimitZone), "road_regulation.kind.speed_limit")
        XCTAssertEqual(textKeys.kindKey(for: .stop), "road_regulation.kind.stop")
        XCTAssertEqual(textKeys.kindKey(for: .oneWay), "road_regulation.kind.one_way")
        XCTAssertEqual(textKeys.kindKey(for: .slowDown), "road_regulation.kind.slow_down")
    }

    /// 判定できない判定は、どの種類でも理由のキーを返します。
    ///
    /// 責務: 4種類の `undeterminable` が、理由のキーと同じになることを全理由で確認します。
    func testUndeterminableVerdictsReturnTheReasonKey() {
        for reason in RoadRegulationUndeterminedReason.allCases {
            let expected = textKeys.key(for: reason)
            XCTAssertEqual(textKeys.key(for: SpeedLimitVerdict.undeterminable(reason)), expected)
            XCTAssertEqual(textKeys.key(for: StopVerdict.undeterminable(reason)), expected)
            XCTAssertEqual(textKeys.key(for: OneWayVerdict.undeterminable(reason)), expected)
            XCTAssertEqual(textKeys.key(for: SlowDownVerdict.undeterminable(reason)), expected)
        }
    }
}
