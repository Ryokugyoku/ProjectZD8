import XCTest
@testable import ProjectZD8

/// 段階的回復の進み方(段階・試行番号・次の動作)を検証します。
final class LiveTelemetryRecoveryProgressTests: XCTestCase {
    /// 失敗を記録するたびに、上限まで同じ段階をやり直し、上限で次の段階へ進み、最後の段階の上限で猶予に入ります。
    ///
    /// 責務: 3段階・各上限回数の遷移と、段階を進めた時の試行番号の戻りを確認します。
    func testFailuresAdvanceThroughStagesThenEnterGrace() {
        var progress = LiveTelemetryRecoveryProgress()
        XCTAssertEqual(progress.stage, .promptResync)
        XCTAssertEqual(progress.attempt, 1)
        var actions: [AcquisitionRecoveryAction] = []
        var stages: [AcquisitionRecoveryStage] = [progress.stage]
        for _ in 0..<(3 + 2 + 3) {
            actions.append(progress.recordFailure())
            stages.append(progress.stage)
        }

        XCTAssertEqual(actions, [
            .retryCurrentStage, .retryCurrentStage, .advance(to: .reinitializeFromReset),
            .retryCurrentStage, .advance(to: .reconnectLink),
            .retryCurrentStage, .retryCurrentStage, .enterGracePeriod
        ])
        XCTAssertEqual(stages, [
            .promptResync, .promptResync, .promptResync, .reinitializeFromReset, .reinitializeFromReset,
            .reconnectLink, .reconnectLink, .reconnectLink, .reconnectLink
        ])
    }

    /// 試行番号は失敗回数+1で、段階を進めると1に戻ります。
    ///
    /// 責務: 試行番号の計算を確認します。
    func testAttemptNumberResetsOnAdvance() {
        var progress = LiveTelemetryRecoveryProgress()
        _ = progress.recordFailure()
        XCTAssertEqual(progress.attempt, 2)
        _ = progress.recordFailure()
        _ = progress.recordFailure()

        XCTAssertEqual(progress.stage, .reinitializeFromReset)
        XCTAssertEqual(progress.failedAttempts, 0)
        XCTAssertEqual(progress.attempt, 1)
    }
}
