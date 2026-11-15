import XCTest
@testable import ProjectZD8

/// 応答途絶の判定と回復段階の進行を検証します。
final class AcquisitionStallPolicyTests: XCTestCase {
    /// 判定対象のPolicyです。
    private let policy = AcquisitionStallPolicy()
    /// 途絶閾値です。
    private let threshold = AcquisitionStallPolicy.stallThresholdNanoseconds

    /// 上限と閾値が判定に意味を持つ範囲であることを確認します。
    ///
    /// 責務: 各段階の上限が1以上、閾値が0より大きいことを確認します。
    func testLimitsAreMeaningful() {
        XCTAssertGreaterThan(threshold, 0)
        for stage in AcquisitionRecoveryStage.allCases {
            XCTAssertGreaterThanOrEqual(policy.attemptLimit(for: stage), 1)
        }
    }

    /// 経過0は途絶ではありません。
    ///
    /// 責務: 受信直後が非途絶であることを確認します。
    func testZeroElapsedIsNotStalled() {
        XCTAssertFalse(policy.isStalled(elapsedSinceLastReceiveNanoseconds: 0))
    }

    /// 閾値の前後で途絶判定が切り替わります。
    ///
    /// 責務: 閾値-1nsは非途絶、ちょうどと+1nsは途絶であることを確認します。
    func testStallThresholdBoundary() {
        XCTAssertFalse(policy.isStalled(elapsedSinceLastReceiveNanoseconds: threshold - 1))
        XCTAssertTrue(policy.isStalled(elapsedSinceLastReceiveNanoseconds: threshold))
        XCTAssertTrue(policy.isStalled(elapsedSinceLastReceiveNanoseconds: threshold + 1))
    }

    /// 回復段階が定義順に3段階並んでいます。
    ///
    /// 責務: 段階の順序が再同期、ATZ再初期化、再接続であることを確認します。
    func testStageOrder() {
        XCTAssertEqual(AcquisitionRecoveryStage.allCases, [.promptResync, .reinitializeFromReset, .reconnectLink])
    }

    /// プロンプト再同期段階の境界を検証します。
    ///
    /// 責務: 0と上限-1は再試行、上限ちょうど・超過は再初期化へ進むことを確認します。
    func testPromptResyncBoundary() {
        assertBoundary(stage: .promptResync, exhausted: .advance(to: .reinitializeFromReset))
    }

    /// ATZ再初期化段階の境界を検証します。
    ///
    /// 責務: 0と上限-1は再試行、上限ちょうど・超過は再接続へ進むことを確認します。
    func testReinitializeFromResetBoundary() {
        assertBoundary(stage: .reinitializeFromReset, exhausted: .advance(to: .reconnectLink))
    }

    /// 再接続段階の境界を検証します。
    ///
    /// 責務: 0と上限-1は再試行、上限ちょうど・超過は猶予待ちへ入ることを確認します。
    func testReconnectLinkBoundary() {
        assertBoundary(stage: .reconnectLink, exhausted: .enterGracePeriod)
    }

    /// 1段階分の失敗回数境界を検証します。
    ///
    /// 責務: 0・上限-1は再試行、上限ちょうど・上限+1は期待動作になることを確認します。
    /// - Parameters:
    ///   - stage: 検証する回復段階。
    ///   - exhausted: 上限に達した時に期待する動作。
    private func assertBoundary(
        stage: AcquisitionRecoveryStage,
        exhausted: AcquisitionRecoveryAction,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let limit = policy.attemptLimit(for: stage)
        XCTAssertEqual(policy.nextAction(after: stage, failedAttempts: 0), .retryCurrentStage, file: file, line: line)
        XCTAssertEqual(policy.nextAction(after: stage, failedAttempts: limit - 1), .retryCurrentStage, file: file, line: line)
        XCTAssertEqual(policy.nextAction(after: stage, failedAttempts: limit), exhausted, file: file, line: line)
        XCTAssertEqual(policy.nextAction(after: stage, failedAttempts: limit + 1), exhausted, file: file, line: line)
    }
}
