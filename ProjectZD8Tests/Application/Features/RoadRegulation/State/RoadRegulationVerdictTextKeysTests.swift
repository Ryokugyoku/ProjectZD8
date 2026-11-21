import XCTest
@testable import ProjectZD8

/// `RoadRegulationVerdictTextKeys` が、判定・理由・種類から文言キーを返すことを検証します(設計書 §2.7、TB9)。
///
/// 期待するキーは、文言の担当が xcstrings に追加したキー(管理役が確定したもの)です。
/// - 理由: `road_regulation.undetermined.<case 名の snake_case>`
/// - 種類: 最高速度の区間・可変区間・区域は `road_regulation.kind.speed_limit` に寄せ、全体で4種類
@MainActor
final class RoadRegulationVerdictTextKeysTests: XCTestCase {
    private let keys = RoadRegulationVerdictTextKeys()

    /// 理由の case と、期待するキーの末尾(snake_case)の表です。
    private let reasonSuffixes: [RoadRegulationUndeterminedReason: String] = [
        .coarseGeometry: "coarse_geometry", .ambiguousCandidates: "ambiguous_candidates", .conditionUnknown: "condition_unknown",
        .variableSpeedLimit: "variable_speed_limit", .oneSidedSection: "one_sided_section", .nearZoneBoundary: "near_zone_boundary",
        .nearExclusionArea: "near_exclusion_area", .headingUnknown: "heading_unknown", .outsideRegulationData: "outside_regulation_data",
        .speedUnavailable: "speed_unavailable", .speedSamplingTooSparse: "speed_sampling_too_sparse",
        .possiblyDifferentRoad: "possibly_different_road", .insufficientDistance: "insufficient_distance",
        .lowAccuracy: "low_accuracy", .trackGap: "track_gap",
    ]

    /// 責務: 理由の全 case が `road_regulation.undetermined.<snake_case>` になることを確かめます。
    func testReasonKeysAreSnakeCaseOfCaseName() {
        XCTAssertEqual(Set(reasonSuffixes.keys), Set(RoadRegulationUndeterminedReason.allCases), "表が全 case を覆っていません")
        for reason in RoadRegulationUndeterminedReason.allCases {
            XCTAssertEqual(keys.key(for: reason), "road_regulation.undetermined.\(reasonSuffixes[reason] ?? "?")", "\(reason)")
        }
    }

    /// 責務: 理由のキーが空でなく、15 case で互いに異なることを確かめます。
    func testReasonKeysAreNonEmptyAndDistinct() {
        let reasonKeys = RoadRegulationUndeterminedReason.allCases.map { keys.key(for: $0) }
        XCTAssertFalse(reasonKeys.contains(""))
        XCTAssertEqual(Set(reasonKeys).count, 15)
    }

    /// 責務: 最高速度の判定のキーを確かめます。
    func testSpeedLimitVerdictKeys() {
        XCTAssertEqual(keys.key(for: SpeedLimitVerdict.withinLimit(maxKph: 38)), "road_regulation.verdict.speed_limit.within_limit")
        XCTAssertEqual(
            keys.key(for: SpeedLimitVerdict.exceeded(maxKph: 52, exceededSeconds: 4)),
            "road_regulation.verdict.speed_limit.exceeded"
        )
        XCTAssertEqual(keys.key(for: SpeedLimitVerdict.unregulated), "road_regulation.verdict.speed_limit.unregulated")
    }

    /// 責務: 一時停止・一方通行・徐行の判定のキーを確かめます。
    func testOtherVerdictKeys() {
        XCTAssertEqual(keys.key(for: StopVerdict.stopped), "road_regulation.verdict.stop.stopped")
        XCTAssertEqual(keys.key(for: StopVerdict.notStopped(minimumKph: 9)), "road_regulation.verdict.stop.not_stopped")
        XCTAssertEqual(keys.key(for: OneWayVerdict.followedDirection), "road_regulation.verdict.one_way.followed_direction")
        XCTAssertEqual(keys.key(for: OneWayVerdict.possibleWrongWay(distanceMeters: 80)), "road_regulation.verdict.one_way.possible_wrong_way")
        XCTAssertEqual(keys.key(for: SlowDownVerdict.observed(maxKph: 14, referenceKph: 10)), "road_regulation.verdict.slow_down.observed")
    }

    /// 責務: 判定のキーが、値に依らず(数値の違う同じ case で)同じになることを確かめます。
    func testVerdictKeysDoNotDependOnValues() {
        XCTAssertEqual(keys.key(for: SpeedLimitVerdict.withinLimit(maxKph: 1)), keys.key(for: SpeedLimitVerdict.withinLimit(maxKph: 99)))
        XCTAssertEqual(keys.key(for: StopVerdict.notStopped(minimumKph: 1)), keys.key(for: StopVerdict.notStopped(minimumKph: 30)))
    }

    /// 責務: 「判定できない」の判定のキーが空でなく、同じ種類のほかの判定のキーと異なることを確かめます(4種類の判定とも)。
    func testUndeterminableVerdictKeysDifferFromOtherVerdicts() {
        let reason = RoadRegulationUndeterminedReason.speedUnavailable
        let groups: [(undeterminable: String, others: [String])] = [
            (keys.key(for: SpeedLimitVerdict.undeterminable(reason)), [
                keys.key(for: SpeedLimitVerdict.withinLimit(maxKph: 1)), keys.key(for: SpeedLimitVerdict.exceeded(maxKph: 1, exceededSeconds: 2)),
                keys.key(for: SpeedLimitVerdict.unregulated),
            ]),
            (keys.key(for: StopVerdict.undeterminable(reason)), [
                keys.key(for: StopVerdict.stopped), keys.key(for: StopVerdict.notStopped(minimumKph: 1)),
            ]),
            (keys.key(for: OneWayVerdict.undeterminable(reason)), [
                keys.key(for: OneWayVerdict.followedDirection), keys.key(for: OneWayVerdict.possibleWrongWay(distanceMeters: 1)),
            ]),
            (keys.key(for: SlowDownVerdict.undeterminable(reason)), [keys.key(for: SlowDownVerdict.observed(maxKph: 1, referenceKph: 10))]),
        ]
        for group in groups {
            XCTAssertFalse(group.undeterminable.isEmpty)
            XCTAssertFalse(group.others.contains(group.undeterminable), group.undeterminable)
        }
    }

    /// 責務: 判定できない以外の判定のキー(8 case)が、空でなく互いに異なることを確かめます。
    func testDeterminedVerdictKeysAreNonEmptyAndDistinct() {
        let verdictKeys: [String] = [
            keys.key(for: SpeedLimitVerdict.withinLimit(maxKph: 1)), keys.key(for: SpeedLimitVerdict.exceeded(maxKph: 1, exceededSeconds: 2)),
            keys.key(for: SpeedLimitVerdict.unregulated), keys.key(for: StopVerdict.stopped), keys.key(for: StopVerdict.notStopped(minimumKph: 1)),
            keys.key(for: OneWayVerdict.followedDirection), keys.key(for: OneWayVerdict.possibleWrongWay(distanceMeters: 1)),
            keys.key(for: SlowDownVerdict.observed(maxKph: 1, referenceKph: 10)),
        ]
        XCTAssertFalse(verdictKeys.contains(""))
        XCTAssertEqual(Set(verdictKeys).count, 8)
    }

    /// 責務: 種類のキーが、最高速度の3種別を `speed_limit` に寄せた4種類になることを確かめます。
    func testKindKeys() {
        let expected: [RoadRegulationKind: String] = [
            .speedLimitSection: "road_regulation.kind.speed_limit", .speedLimitVariableSection: "road_regulation.kind.speed_limit",
            .speedLimitZone: "road_regulation.kind.speed_limit", .stop: "road_regulation.kind.stop",
            .oneWay: "road_regulation.kind.one_way", .slowDown: "road_regulation.kind.slow_down",
        ]
        XCTAssertEqual(Set(expected.keys), Set(RoadRegulationKind.allCases), "表が全 case を覆っていません")
        for kind in RoadRegulationKind.allCases {
            XCTAssertEqual(keys.kindKey(for: kind), expected[kind], "\(kind)")
        }
        XCTAssertEqual(Set(RoadRegulationKind.allCases.map { keys.kindKey(for: $0) }).count, 4)
    }
}
