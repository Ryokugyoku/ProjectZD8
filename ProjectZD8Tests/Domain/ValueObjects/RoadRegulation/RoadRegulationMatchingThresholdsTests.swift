import XCTest
@testable import ProjectZD8

/// `RoadRegulationMatchingThresholds.standard` が設計書 §3.2 の表の値を持ち、式が境界で正しいことを検証します。
final class RoadRegulationMatchingThresholdsTests: XCTestCase {
    private let standard = RoadRegulationMatchingThresholds.standard

    /// 責務: 候補と精度に関する初期値が表のとおりであることを確かめます。
    func testCandidateAndAccuracyValues() {
        XCTAssertEqual(standard.searchRadiusMeters, 120)
        XCTAssertEqual(standard.maximumUsableHorizontalAccuracyMeters, 50)
        XCTAssertEqual(standard.exitHysteresisMeters, 10)
        XCTAssertEqual(standard.headingAlignmentDegrees, 40)
        XCTAssertEqual(standard.reverseHeadingDegrees, 140)
        XCTAssertEqual(standard.headingPenaltyMetersPerDegree, 0.2)
        XCTAssertEqual(standard.currentRegulationBonusMeters, 5)
        XCTAssertEqual(standard.ambiguityMarginMeters, 3)
        XCTAssertEqual(standard.confirmationPoints, 3)
        XCTAssertEqual(standard.maximumTrackGapSeconds, 10)
    }

    /// 責務: 向き・粗い線分・区域の境目に関する初期値が表のとおりであることを確かめます。
    func testHeadingAndCoarseValues() {
        XCTAssertEqual(standard.minimumCourseSpeedMetersPerSecond, 1.5)
        XCTAssertEqual(standard.minimumHeadingDisplacementMeters, 5)
        XCTAssertEqual(standard.coarseSegmentLengthMeters, 1_000)
        XCTAssertEqual(standard.coarseCorridorMeters, 100)
        XCTAssertEqual(standard.zoneBoundaryMarginMeters, 20)
        XCTAssertEqual(standard.lateralToleranceBaseMeters, 12)
        XCTAssertEqual(standard.lateralToleranceMinimumMeters, 15)
        XCTAssertEqual(standard.lateralToleranceMaximumMeters, 35)
    }

    /// 責務: 最高速度に関する初期値が表のとおりであることを確かめます。
    func testSpeedLimitValues() {
        XCTAssertEqual(standard.speedToleranceMinimumKph, 3)
        XCTAssertEqual(standard.speedToleranceFraction, 0.05)
        XCTAssertEqual(standard.minimumExceedDurationSeconds, 2)
        XCTAssertEqual(standard.maximumExceedRunGapSeconds, 3)
        XCTAssertEqual(standard.maximumSpeedSampleGapSeconds, 5)
        XCTAssertEqual(standard.implausibleExcessKph, 40)
    }

    /// 責務: 一時停止に関する初期値が表のとおりであることを確かめます。
    func testStopValues() {
        XCTAssertEqual(standard.stopApproachLengthMeters, 40)
        XCTAssertEqual(standard.stopReachMeters, 5)
        XCTAssertEqual(standard.stopLateralToleranceBaseMeters, 8)
        XCTAssertEqual(standard.stopLateralToleranceMinimumMeters, 10)
        XCTAssertEqual(standard.stopLateralToleranceMaximumMeters, 20)
        XCTAssertEqual(standard.stopHeadingDegrees, 45)
        XCTAssertEqual(standard.stopAbandonExtraMeters, 10)
        XCTAssertEqual(standard.stopAbandonHeadingDegrees, 90)
        XCTAssertEqual(standard.minimumStopApproachVectorMeters, 2)
        XCTAssertEqual(standard.stoppedSpeedKph, 0.5)
        XCTAssertEqual(standard.stopEvidenceMarginSeconds, 1)
        XCTAssertEqual(standard.stopBracketMaximumSeconds, 3)
        XCTAssertEqual(standard.maximumDecelerationMps2, 5)
        XCTAssertEqual(standard.stopRearmDistanceMeters, 60)
    }

    /// 責務: 一方通行・徐行に関する初期値が表のとおりであることを確かめます。
    func testWrongWayAndSlowDownValues() {
        XCTAssertEqual(standard.wrongWayMinimumDistanceMeters, 50)
        XCTAssertEqual(standard.wrongWayShortSectionMinimumMeters, 20)
        XCTAssertEqual(standard.wrongWayShortSectionFraction, 0.8)
        XCTAssertEqual(standard.wrongWayMaximumAccuracyMeters, 20)
        XCTAssertEqual(standard.slowDownReferenceKph, 10)
    }

    /// 責務: 横方向の許容 clamp(12 + 精度, 15, 35) の下限・中間・上限の境界を確かめます。
    func testLateralToleranceClamp() {
        XCTAssertEqual(standard.lateralTolerance(accuracy: 0), 15, accuracy: 1e-9)
        XCTAssertEqual(standard.lateralTolerance(accuracy: 3), 15, accuracy: 1e-9)
        XCTAssertEqual(standard.lateralTolerance(accuracy: 3.5), 15.5, accuracy: 1e-9)
        XCTAssertEqual(standard.lateralTolerance(accuracy: 10), 22, accuracy: 1e-9)
        XCTAssertEqual(standard.lateralTolerance(accuracy: 23), 35, accuracy: 1e-9)
        XCTAssertEqual(standard.lateralTolerance(accuracy: 30), 35, accuracy: 1e-9)
        XCTAssertEqual(standard.lateralTolerance(accuracy: 500), 35, accuracy: 1e-9)
    }

    /// 責務: 一時停止の横方向の許容 clamp(8 + 精度, 10, 20) の下限・中間・上限の境界を確かめます。
    func testStopLateralToleranceClamp() {
        XCTAssertEqual(standard.stopLateralTolerance(accuracy: 0), 10, accuracy: 1e-9)
        XCTAssertEqual(standard.stopLateralTolerance(accuracy: 2), 10, accuracy: 1e-9)
        XCTAssertEqual(standard.stopLateralTolerance(accuracy: 5), 13, accuracy: 1e-9)
        XCTAssertEqual(standard.stopLateralTolerance(accuracy: 12), 20, accuracy: 1e-9)
        XCTAssertEqual(standard.stopLateralTolerance(accuracy: 40), 20, accuracy: 1e-9)
    }

    /// 責務: 速度の許容 max(3, ceil(L × 0.05)) が、L = 40 で 3、L = 80 で 4 などの値になることを確かめます。
    func testSpeedToleranceFormula() {
        XCTAssertEqual(standard.speedTolerance(limitKph: 30), 3)
        XCTAssertEqual(standard.speedTolerance(limitKph: 40), 3)
        XCTAssertEqual(standard.speedTolerance(limitKph: 60), 3)
        XCTAssertEqual(standard.speedTolerance(limitKph: 61), 4)
        XCTAssertEqual(standard.speedTolerance(limitKph: 80), 4)
        XCTAssertEqual(standard.speedTolerance(limitKph: 100), 5)
        XCTAssertEqual(standard.speedTolerance(limitKph: 101), 6)
        XCTAssertEqual(standard.speedTolerance(limitKph: 0), 3)
    }

    /// 責務: 逆走の必要距離 min(50, max(20, 0.8 × 区間長)) の短い区間・中間・長い区間の境界を確かめます。
    func testWrongWayRequiredDistanceFormula() {
        XCTAssertEqual(standard.wrongWayRequiredDistance(regulationLengthMeters: 10), 20, accuracy: 1e-9)
        XCTAssertEqual(standard.wrongWayRequiredDistance(regulationLengthMeters: 25), 20, accuracy: 1e-9)
        XCTAssertEqual(standard.wrongWayRequiredDistance(regulationLengthMeters: 30), 24, accuracy: 1e-9)
        XCTAssertEqual(standard.wrongWayRequiredDistance(regulationLengthMeters: 62.5), 50, accuracy: 1e-9)
        XCTAssertEqual(standard.wrongWayRequiredDistance(regulationLengthMeters: 62), 49.6, accuracy: 1e-9)
        XCTAssertEqual(standard.wrongWayRequiredDistance(regulationLengthMeters: 500), 50, accuracy: 1e-9)
    }
}
