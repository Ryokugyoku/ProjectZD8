import XCTest
@testable import ProjectZD8

/// 回復中・一時停止中の表示状態と文言キーを検証します。
final class LiveTelemetryPauseStatusTests: XCTestCase {
    /// 取得中には表示状態が無く、回復中と一時停止中にはあります。
    ///
    /// 責務: 生成の可否を確認します。
    func testExistsOnlyOutsideAcquiring() {
        XCTAssertNil(LiveTelemetryPauseStatus(.acquiring))
        XCTAssertNotNil(LiveTelemetryPauseStatus(.recovering(cause: .linkLost, stage: .promptResync, attempt: 1)))
        XCTAssertNotNil(LiveTelemetryPauseStatus(.paused(cause: .responseStall)))
    }

    /// 回復中かどうかは回復のフェーズだけで真です。
    ///
    /// 責務: 回復中と一時停止中の判定を確認します。
    func testIsRecovering() {
        XCTAssertEqual(LiveTelemetryPauseStatus(.recovering(cause: .responseStall, stage: .reconnectLink, attempt: 3))?.isRecovering, true)
        XCTAssertEqual(LiveTelemetryPauseStatus(.paused(cause: .linkLost))?.isRecovering, false)
    }

    /// 文言キーは回復の段階ごと、一時停止の原因ごとに異なります。
    ///
    /// 責務: 5つの表示状態の文言キーを確認します。
    func testStatusKeyForEachPhase() {
        let cases: [(LiveTelemetryAcquisitionPhase, String)] = [
            (.recovering(cause: .linkLost, stage: .promptResync, attempt: 2), "telemetry.status.recovering.prompt_resync"),
            (.recovering(cause: .linkLost, stage: .reinitializeFromReset, attempt: 1), "telemetry.status.recovering.reinitialize"),
            (.recovering(cause: .responseStall, stage: .reconnectLink, attempt: 1), "telemetry.status.recovering.reconnect"),
            (.paused(cause: .responseStall), "telemetry.status.paused.no_response"),
            (.paused(cause: .linkLost), "telemetry.status.paused.link_lost")
        ]
        for (phase, key) in cases {
            XCTAssertEqual(LiveTelemetryPauseStatus(phase)?.statusKey, key, "\(phase)")
        }
    }
}
