import XCTest
@testable import ProjectZD8

/// 取得ループの診断文言が、実機テスト手順書が参照する固定文字列と完全一致することを検証します。
@MainActor
final class LiveTelemetryAcquisitionDiagnosticsMessageFormatterTests: XCTestCase {
    /// テスト対象の整形器です。
    private let formatter = LiveTelemetryAcquisitionDiagnosticsMessageFormatter()

    /// 開始と、原因を持たない終了の固定文言を確認します。
    ///
    /// 責務: 引数を取らない各メソッドの文字列を確認します。
    func testFixedMessages() {
        XCTAssertEqual(formatter.started(), "Acquisition started")
        XCTAssertEqual(formatter.stopped(), "Acquisition ended: stopped")
        XCTAssertEqual(formatter.recordingFailed(), "Acquisition ended: recordingFailed")
    }

    /// 取得中の段階の文言を確認します。
    ///
    /// 責務: `acquiring` の文字列を確認します。
    func testAcquiringPhase() {
        XCTAssertEqual(formatter.phaseChanged(.acquiring), "Acquisition phase: acquiring")
    }

    /// 仕様の例どおりの回復中の文言を確認します。
    ///
    /// 責務: 原因 responseStall・段階 promptResync・試行1の文字列を確認します。
    func testRecoveringPhaseExample() {
        XCTAssertEqual(
            formatter.phaseChanged(.recovering(cause: .responseStall, stage: .promptResync, attempt: 1)),
            "Acquisition phase: recovering cause=responseStall stage=promptResync attempt=1"
        )
    }

    /// 回復中の文言を、原因2通り × 段階3通り × 試行番号複数で確認します。
    ///
    /// 責務: 原因・段階・試行番号がそれぞれ文言の決まった位置へ入ることを網羅します。
    func testRecoveringPhaseForEveryCauseStageAndAttempts() {
        let causes: [(LiveTelemetryInterruptionCause, String)] = [(.responseStall, "responseStall"), (.linkLost, "linkLost")]
        let stages: [(AcquisitionRecoveryStage, String)] = [
            (.promptResync, "promptResync"),
            (.reinitializeFromReset, "reinitializeFromReset"),
            (.reconnectLink, "reconnectLink")
        ]
        for (cause, causeName) in causes {
            for (stage, stageName) in stages {
                for attempt in [1, 3, 12] {
                    XCTAssertEqual(
                        formatter.phaseChanged(.recovering(cause: cause, stage: stage, attempt: attempt)),
                        "Acquisition phase: recovering cause=\(causeName) stage=\(stageName) attempt=\(attempt)"
                    )
                }
            }
        }
    }

    /// 一時停止の文言を原因2通りで確認します。
    ///
    /// 責務: `paused` の原因が文言へ入ることを確認します。
    func testPausedPhaseForEveryCause() {
        XCTAssertEqual(formatter.phaseChanged(.paused(cause: .responseStall)), "Acquisition phase: paused cause=responseStall")
        XCTAssertEqual(formatter.phaseChanged(.paused(cause: .linkLost)), "Acquisition phase: paused cause=linkLost")
    }

    /// 猶予切れの終了の文言を原因2通りで確認します。
    ///
    /// 責務: `gracePeriodExpired` の原因が文言へ入ることを確認します。
    func testGracePeriodExpiredForEveryCause() {
        XCTAssertEqual(formatter.gracePeriodExpired(cause: .responseStall), "Acquisition ended: gracePeriodExpired cause=responseStall")
        XCTAssertEqual(formatter.gracePeriodExpired(cause: .linkLost), "Acquisition ended: gracePeriodExpired cause=linkLost")
    }
}
