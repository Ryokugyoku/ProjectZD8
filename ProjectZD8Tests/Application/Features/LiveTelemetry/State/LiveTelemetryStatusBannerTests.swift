import XCTest
@testable import ProjectZD8

/// フェーズ・一時停止状態・失敗キーから状態バナーの文言キー・記号・色調・進行表示を決める規則を検証します。
@MainActor
final class LiveTelemetryStatusBannerTests: XCTestCase {
    private typealias Fixture = LiveTelemetryPanelTestFixture

    /// 読み込み中は受信待ちの文言と電波の記号で、進行表示を伴う強調色になります。
    ///
    /// 責務: reading の4項目を確かめます。
    func testReading() throws {
        let banner = try XCTUnwrap(LiveTelemetryStatusBanner(state: Fixture.state(phase: .reading)))

        XCTAssertEqual(banner.key, "telemetry.status.reading")
        XCTAssertEqual(banner.symbol, "dot.radiowaves.left.and.right")
        XCTAssertEqual(banner.tone, .active)
        XCTAssertTrue(banner.showsProgress)
    }

    /// 受信中は取得中の文言と波形の記号で、進行表示のない正常色になります。
    ///
    /// 責務: loaded の4項目を確かめます。
    func testLoaded() throws {
        let banner = try XCTUnwrap(LiveTelemetryStatusBanner(state: Fixture.state(phase: .loaded)))

        XCTAssertEqual(banner.key, "telemetry.status.polling")
        XCTAssertEqual(banner.symbol, "waveform.path.ecg")
        XCTAssertEqual(banner.tone, .healthy)
        XCTAssertFalse(banner.showsProgress)
    }

    /// 受信中は失敗キーが残っていても受信中の文言を出します。
    ///
    /// 責務: loaded で failureKey を使わないことを確かめます。
    func testLoadedIgnoresFailureKey() throws {
        let banner = try XCTUnwrap(LiveTelemetryStatusBanner(state: Fixture.state(phase: .loaded, failureKey: "test.failure")))

        XCTAssertEqual(banner.key, "telemetry.status.polling")
    }

    /// 回復中の一時停止は回復の文言と一時停止の記号で、進行表示を伴う警告色になります。
    ///
    /// 責務: paused で回復中の pauseStatus がある時の4項目を確かめます。
    func testPausedWhileRecovering() throws {
        let pauseStatus = try XCTUnwrap(LiveTelemetryPauseStatus(.recovering(cause: .linkLost, stage: .reconnectLink, attempt: 1)))
        let banner = try XCTUnwrap(LiveTelemetryStatusBanner(state: Fixture.state(phase: .paused, pauseStatus: pauseStatus)))

        XCTAssertEqual(banner.key, "telemetry.status.recovering.reconnect")
        XCTAssertEqual(banner.symbol, "pause.circle")
        XCTAssertEqual(banner.tone, .warning)
        XCTAssertTrue(banner.showsProgress)
    }

    /// 回復を諦めた一時停止は原因の文言で、進行表示のない警告色になります。
    ///
    /// 責務: paused で回復中でない pauseStatus がある時の4項目を確かめます。
    func testPausedWithoutRecovery() throws {
        let pauseStatus = try XCTUnwrap(LiveTelemetryPauseStatus(.paused(cause: .responseStall)))
        let banner = try XCTUnwrap(LiveTelemetryStatusBanner(state: Fixture.state(phase: .paused, pauseStatus: pauseStatus)))

        XCTAssertEqual(banner.key, "telemetry.status.paused.no_response")
        XCTAssertEqual(banner.symbol, "pause.circle")
        XCTAssertEqual(banner.tone, .warning)
        XCTAssertFalse(banner.showsProgress)
    }

    /// 一時停止でも表示状態が無ければバナーを作りません。
    ///
    /// 責務: paused で pauseStatus が nil の時に nil を確かめます。
    func testPausedWithoutPauseStatusHasNoBanner() {
        XCTAssertNil(LiveTelemetryStatusBanner(state: Fixture.state(phase: .paused)))
    }

    /// 切断中は切断中の文言と停止の記号で、進行表示を伴う警告色になります。
    ///
    /// 責務: stopping の4項目を確かめます。
    func testStopping() throws {
        let banner = try XCTUnwrap(LiveTelemetryStatusBanner(state: Fixture.state(phase: .stopping)))

        XCTAssertEqual(banner.key, "telemetry.status.stopping")
        XCTAssertEqual(banner.symbol, "stop.circle")
        XCTAssertEqual(banner.tone, .warning)
        XCTAssertTrue(banner.showsProgress)
    }

    /// 失敗は失敗キーをそのまま出し、警告の三角の記号で進行表示はありません。
    ///
    /// 責務: failed で failureKey がある時の4項目を確かめます。
    func testFailedWithFailureKey() throws {
        let banner = try XCTUnwrap(LiveTelemetryStatusBanner(state: Fixture.state(phase: .failed, failureKey: "test.failure")))

        XCTAssertEqual(banner.key, "test.failure")
        XCTAssertEqual(banner.symbol, "exclamationmark.triangle.fill")
        XCTAssertEqual(banner.tone, .warning)
        XCTAssertFalse(banner.showsProgress)
    }

    /// 失敗キーの無い失敗は読み取り失敗の既定キーを出します。
    ///
    /// 責務: failed で failureKey が nil の時の4項目を確かめます。
    func testFailedWithoutFailureKeyUsesReadFailedKey() throws {
        let banner = try XCTUnwrap(LiveTelemetryStatusBanner(state: Fixture.state(phase: .failed)))

        XCTAssertEqual(banner.key, "telemetry.error.read_failed")
        XCTAssertEqual(banner.symbol, "exclamationmark.triangle.fill")
        XCTAssertEqual(banner.tone, .warning)
        XCTAssertFalse(banner.showsProgress)
    }

    /// 待機中でも失敗キーが残っていれば、失敗と同じ形のバナーを出します。
    ///
    /// 責務: idle で failureKey がある時の4項目を確かめます。
    func testIdleWithFailureKey() throws {
        let state = Fixture.state(phase: .idle, failureKey: "telemetry.disconnected.test")
        let banner = try XCTUnwrap(LiveTelemetryStatusBanner(state: state))

        XCTAssertEqual(banner.key, "telemetry.disconnected.test")
        XCTAssertEqual(banner.symbol, "exclamationmark.triangle.fill")
        XCTAssertEqual(banner.tone, .warning)
        XCTAssertFalse(banner.showsProgress)
    }

    /// 失敗キーの無い待機中はバナーを作りません。
    ///
    /// 責務: idle で failureKey が nil の時に nil を確かめます。
    func testIdleWithoutFailureKeyHasNoBanner() {
        XCTAssertNil(LiveTelemetryStatusBanner(state: Fixture.state(phase: .idle)))
    }
}
