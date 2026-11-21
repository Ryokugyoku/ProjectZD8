import XCTest
@testable import ProjectZD8

/// `SessionRoadRegulationEvaluator` が、合成した軌跡・車速・規制から1セッションの判定の結果を出すことを検証します
/// (設計書 §2.7・§3.5・§3.6、TB9)。場面は `RoadRegulationEvaluationScenario` を参照してください。
///
/// 期待値は §3.2 のしきい値と §3.5 の規則から求めます(精度 5 m の許容 17 m、いま乗っている候補 27 m、確定 3 点)。
/// - 最高速度の区間: x = 0 の点(連番 0)で乗り、x = 430 から外れる(400 から 30 m > 27 m)ので、区間は連番 0〜42。
/// - 徐行: x = 490(端から 10 m)で乗り、x = 730 から外れるので、区間は連番 49〜72。
/// - 一方通行: x = 790 で逆方向に乗り、x = 1,030 から外れるので、区間は連番 79〜102、逆向きの距離 D = 230 m(必要な距離 50 m)。
/// - 一時停止: s = x − 1,153。x = 1,120(s = −33、連番 112)で開始し、x = 1,150(s = −3、連番 115)で到達する。
@MainActor
final class SessionRoadRegulationEvaluatorTests: XCTestCase {
    private typealias Scenario = RoadRegulationEvaluationScenario

    /// 責務: 最高速度の判定のうち、規制のある区間のものだけを返します。
    private func regulatedSpeedLimit(_ report: SessionRoadRegulationReport) -> [SpeedLimitJudgement] {
        report.speedLimit.filter { judgement in
            if case .speedLimit(.regulated) = judgement.traversal.status { return true }
            return false
        }
    }

    /// 責務: 制限内で走る場面で、4種類の判定が1件ずつ期待どおりに出ることを確かめます。
    func testCombinedScenarioProducesOneJudgementPerRegulation() throws {
        let report = Scenario.evaluate(speeds: Scenario.speeds(35))
        let speed = regulatedSpeedLimit(report)

        XCTAssertEqual(speed.count, 1)
        XCTAssertEqual(speed.first?.limitKph, 40)
        XCTAssertEqual(speed.first?.verdict, .withinLimit(maxKph: 35))
        XCTAssertEqual(speed.first?.traversal.start.sequence, 0)
        XCTAssertEqual(speed.first?.traversal.end.sequence, 42)
        XCTAssertEqual(report.speedLimit.map(\.verdict), [.withinLimit(maxKph: 35), .unregulated])
        XCTAssertEqual(report.slowDown.map(\.verdict), [.observed(maxKph: 35, referenceKph: 10)])
        XCTAssertEqual(report.stops.map(\.verdict), [.notStopped(minimumKph: 35)])
        XCTAssertEqual(report.oneWay.count, 1)
        let oneWay = try XCTUnwrap(report.oneWay.first)
        guard case .possibleWrongWay(let distance) = oneWay.verdict else {
            return XCTFail("逆走の可能性になりませんでした: \(oneWay.verdict)")
        }
        XCTAssertEqual(distance, 230, accuracy: 0.5)
    }

    /// 責務: 区間・徐行・一方通行・一時停止の通過の範囲(連番)が、規則から求めた値になることを確かめます。
    func testTraversalRangesFollowMatchingRules() throws {
        let report = Scenario.evaluate(speeds: Scenario.speeds(35))
        let slowDown = try XCTUnwrap(report.slowDown.first)
        let oneWay = try XCTUnwrap(report.oneWay.first)
        let stop = try XCTUnwrap(report.stops.first)

        XCTAssertEqual(slowDown.traversal.start.sequence, 49)
        XCTAssertEqual(slowDown.traversal.end.sequence, 72)
        XCTAssertEqual(oneWay.traversal.status, .oneWay(.on(RoadRegulationID(rawValue: 3), .reverse)))
        XCTAssertEqual(oneWay.traversal.start.sequence, 79)
        XCTAssertEqual(oneWay.traversal.end.sequence, 102)
        XCTAssertEqual(stop.passage.key, StopApproachKey(regulationID: RoadRegulationID(rawValue: 4), approachIndex: 0))
        XCTAssertEqual(stop.passage.approachStarted.sequence, 112)
        XCTAssertEqual(stop.passage.reached.sequence, 115)
        XCTAssertFalse(stop.passage.interruptedByGap)
    }

    /// 責務: 制限 40 の区間を 50 km/h で走ると、区間の窓 0〜42 秒の全体が超過(50、42 秒)になることを確かめます。
    func testExceedingSpeedIsExceeded() throws {
        let report = Scenario.evaluate(speeds: Scenario.speeds(50))
        let judgement = try XCTUnwrap(regulatedSpeedLimit(report).first)
        guard case .exceeded(let maxKph, let seconds) = judgement.verdict else {
            return XCTFail("超過になりませんでした: \(judgement.verdict)")
        }
        XCTAssertEqual(maxKph, 50, accuracy: 0.001)
        XCTAssertEqual(seconds, 42, accuracy: 0.001)
    }

    /// 責務: 一時停止の窓(開始 −1 〜 到達 +1 秒)に 0 km/h があれば `stopped`、無ければ `notStopped` になることを確かめます。
    func testStopVerdictFollowsVehicleSpeed() {
        let stopped = Scenario.evaluate(speeds: Scenario.speeds(35, overrides: [112: 0, 113: 0, 114: 0, 115: 0]))
        let moving = Scenario.evaluate(speeds: Scenario.speeds(35))
        XCTAssertEqual(stopped.stops.map(\.verdict), [.stopped])
        XCTAssertEqual(moving.stops.map(\.verdict), [.notStopped(minimumKph: 35)])
    }

    /// 責務: 車速が無いと、車速の要る判定が `speedUnavailable` になり、判定できない件数と理由の内訳が集計に入ることを確かめます。
    func testMissingSpeedsAreUndeterminedAndCounted() throws {
        let report = Scenario.evaluate(speeds: VehicleSpeedTimeline(samples: []))

        XCTAssertEqual(regulatedSpeedLimit(report).map(\.verdict), [.undeterminable(.speedUnavailable)])
        XCTAssertEqual(report.stops.map(\.verdict), [.undeterminable(.speedUnavailable)])
        XCTAssertEqual(report.slowDown.map(\.verdict), [.undeterminable(.speedUnavailable)])
        XCTAssertEqual(report.speedLimitTally.total, 2)
        XCTAssertEqual(report.speedLimitTally.undetermined, 1)
        XCTAssertEqual(report.speedLimitTally.undeterminedByReason, [.speedUnavailable: 1])
        XCTAssertEqual(report.stopTally.undetermined, 1)
        XCTAssertEqual(report.slowDownTally.undeterminedByReason, [.speedUnavailable: 1])
        XCTAssertEqual(report.oneWayTally.undetermined, 0)
        XCTAssertFalse(report.coverage.hasVehicleSpeed)
    }

    /// 責務: 版の範囲(x ≤ 605 m)を出た点からの区間が `outsideRegulationData` になり、集計の内訳に入ることを確かめます。
    func testPointsOutsideCoverageAreUndeterminable() {
        let report = Scenario.evaluate(speeds: Scenario.speeds(35), coverage: [Scenario.coverage(east: 605)])
        let outside = report.speedLimit.filter { $0.verdict == .undeterminable(.outsideRegulationData) }

        XCTAssertEqual(outside.count, 1)
        XCTAssertEqual(outside.first?.traversal.start.sequence, 61)
        XCTAssertEqual(outside.first?.traversal.endReason, .trackEnded)
        XCTAssertEqual(report.speedLimitTally.undeterminedByReason[.outsideRegulationData], 1)
    }

    /// 責務: 結果の `coverage` に、時刻の軸・点の数・捨てた点の数・車速の有無・版の参照が入ることを確かめます。
    func testCoverageCarriesInputs() {
        let report = Scenario.evaluate(speeds: Scenario.speeds(35), droppedPointCount: 7, timeAxis: .wallClock)
        XCTAssertEqual(
            report.coverage,
            RoadRegulationEvaluationCoverage(
                timeAxis: .wallClock,
                trackPointCount: Scenario.pointCount,
                droppedPointCount: 7,
                hasVehicleSpeed: true,
                datasets: Scenario.datasets
            )
        )
    }

    /// 責務: 末尾に精度 60 m の点があっても無視し、最後の区間を最後の使える点(連番 120)で閉じることを確かめます。
    func testInaccurateTrailingPointIsNotRecorded() {
        let inaccurate = RoadRegulationMeterTrackPointFactory.point(sequence: 121, x: 1_210, y: 0, accuracy: 60, course: 90, speed: 10)
        let report = Scenario.evaluate(speeds: Scenario.speeds(35), track: Scenario.track() + [inaccurate])
        XCTAssertEqual(report.speedLimit.last?.verdict, .unregulated)
        XCTAssertEqual(report.speedLimit.last?.traversal.end.sequence, 120)
        XCTAssertEqual(report.speedLimit.last?.traversal.endReason, .trackEnded)
    }

    /// 責務: 軌跡が空なら、判定も集計も空(件数0)で、`coverage` の点の数が0になることを確かめます。
    func testEmptyTrackGivesEmptyReport() {
        let report = Scenario.evaluate(speeds: Scenario.speeds(35), track: [])
        XCTAssertEqual(report.speedLimit, [])
        XCTAssertEqual(report.stops, [])
        XCTAssertEqual(report.oneWay, [])
        XCTAssertEqual(report.slowDown, [])
        XCTAssertEqual(report.speedLimitTally.total, 0)
        XCTAssertEqual(report.coverage.trackPointCount, 0)
    }

    /// 責務: 2万点(1 m ごと・1 Hz)の軌跡を時間の上限(30 秒)内に処理し、区間が1つで両端が最初と最後の点になることを確かめます。
    func testLargeTrackFinishesWithinTimeLimit() async throws {
        let count = 20_000
        let line = RoadRegulationMeterRegulationFactory.line(id: 1, points: (0...40).map { (x: Double($0) * 500, y: 0) })
        let track: [RoadRegulationTrackPoint] = (0..<count).map { index in
            RoadRegulationMeterTrackPointFactory.point(sequence: Int64(index), x: Double(index), y: 0, course: 90, speed: 10)
        }
        let speeds = Scenario.speeds(30, count: count)
        let coverage = [Scenario.coverage(east: 21_000)]
        let index = RoadRegulationSpatialIndex(regulations: [line])
        let datasets = Scenario.datasets
        let run = TestBoundedAsyncRun<SessionRoadRegulationReport> {
            await Task.detached {
                SessionRoadRegulationEvaluator().evaluate(
                    track: track, droppedPointCount: 0, speeds: speeds, index: index,
                    coverage: coverage, timeAxis: .monotonic, datasets: datasets
                )
            }.value
        }
        guard let report = await run.value(on: self, seconds: 30) else { return }

        XCTAssertEqual(report.speedLimit.count, 1)
        XCTAssertEqual(report.speedLimit.first?.verdict, .withinLimit(maxKph: 30))
        XCTAssertEqual(report.speedLimit.first?.traversal.start.sequence, 0)
        XCTAssertEqual(report.speedLimit.first?.traversal.end.sequence, Int64(count - 1))
        XCTAssertEqual(report.speedLimit.first?.traversal.endReason, .trackEnded)
    }
}
