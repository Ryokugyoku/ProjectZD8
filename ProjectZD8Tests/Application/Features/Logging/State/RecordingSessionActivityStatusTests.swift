import XCTest
@testable import ProjectZD8

/// 記録中表示の状態欄が、取得段階ごとに仕様どおりの文言キーと強調になることを検証します。
@MainActor
final class RecordingSessionActivityStatusTests: XCTestCase {
    /// 取得段階から状態欄を作ります。
    ///
    /// 責務: テスト用の状態を状態欄へ変換します。
    private func status(
        _ phase: LiveTelemetryState.Phase,
        pause: LiveTelemetryAcquisitionPhase? = nil,
        failureKey: String? = nil
    ) -> RecordingSessionActivityStatus {
        RecordingSessionActivityStatus(
            telemetry: RecordingSessionActivityTestSupport.state(phase, pause: pause, failureKey: failureKey)
        )
    }

    /// 探索中は「読み取り中」の文言キーで通常の強調です。
    ///
    /// 責務: reading の文言キーと強調を確認します。
    func testReadingIsNormal() {
        let result = status(.reading)
        XCTAssertEqual(result.key, "live_activity.status.reading")
        XCTAssertEqual(result.tone, .normal)
    }

    /// 継続取得中は「記録中」の文言キーで通常の強調です。
    ///
    /// 責務: loaded の文言キーと強調を確認します。
    func testLoadedIsRecordingNormal() {
        let result = status(.loaded)
        XCTAssertEqual(result.key, "live_activity.status.recording")
        XCTAssertEqual(result.tone, .normal)
    }

    /// 停止処理中は「停止中」の文言キーで通常の強調です。
    ///
    /// 責務: stopping の文言キーと強調を確認します。
    func testStoppingIsNormal() {
        let result = status(.stopping)
        XCTAssertEqual(result.key, "live_activity.status.stopping")
        XCTAssertEqual(result.tone, .normal)
    }

    /// 失敗は失敗の文言キーで警告の強調です。
    ///
    /// 責務: failed の文言キーと強調を確認します。
    func testFailedIsWarning() {
        let result = status(.failed)
        XCTAssertEqual(result.key, "live_activity.status.failed")
        XCTAssertEqual(result.tone, .warning)
    }

    /// 一時停止は原因ごとの文言キーで、すべて警告の強調です。
    ///
    /// 責務: 一時停止の全ての取得ループ段階(回復3段階・無応答・リンク断)を網羅します。
    func testPausedUsesPauseStatusKeyForEveryCaseAndIsWarning() {
        let cases: [(LiveTelemetryAcquisitionPhase, String)] = [
            (.recovering(cause: .linkLost, stage: .promptResync, attempt: 1), "telemetry.status.recovering.prompt_resync"),
            (.recovering(cause: .linkLost, stage: .reinitializeFromReset, attempt: 1), "telemetry.status.recovering.reinitialize"),
            (.recovering(cause: .responseStall, stage: .reconnectLink, attempt: 2), "telemetry.status.recovering.reconnect"),
            (.paused(cause: .responseStall), "telemetry.status.paused.no_response"),
            (.paused(cause: .linkLost), "telemetry.status.paused.link_lost")
        ]
        for (phase, key) in cases {
            let result = status(.paused, pause: phase)
            XCTAssertEqual(result.key, key, "\(phase)")
            XCTAssertEqual(result.tone, .warning, "\(phase)")
        }
    }

    /// 原因を持たない一時停止は汎用の一時停止キーで警告です。
    ///
    /// 責務: pauseStatus が無い paused のフォールバックを確認します。
    func testPausedWithoutCauseFallsBackToPausedKey() {
        let result = status(.paused)
        XCTAssertEqual(result.key, "live_activity.status.paused")
        XCTAssertEqual(result.tone, .warning)
    }

    /// 失敗キーの無い待機は「終了」で通常の強調です。
    ///
    /// 責務: idle で正常終了した場合の文言キーと強調を確認します。
    func testIdleWithoutFailureIsEndedNormal() {
        let result = status(.idle)
        XCTAssertEqual(result.key, "live_activity.status.ended")
        XCTAssertEqual(result.tone, .normal)
    }

    /// 失敗キーのある待機(猶予切れ等)はその失敗キーで警告の強調です。
    ///
    /// 責務: idle に失敗キーがある場合に、そのキーと警告になることを確認します。
    func testIdleWithFailureKeyShowsFailureKeyAsWarning() {
        let result = status(.idle, failureKey: "telemetry.disconnected.no_response")
        XCTAssertEqual(result.key, "telemetry.disconnected.no_response")
        XCTAssertEqual(result.tone, .warning)
    }
}
