import XCTest
@testable import ProjectZD8

/// 記録中表示の更新の間引きが、仕様の間隔・同一内容・状態キー変化の規則に従うことを検証します。
@MainActor
final class RecordingSessionActivityUpdateThrottleTests: XCTestCase {
    /// 基準時刻です。
    private let base = Date(timeIntervalSince1970: 10_000)

    /// 指定の受信件数・状態の内容を作ります。
    ///
    /// 責務: 件数と段階だけが異なる内容を返します。
    private func content(_ count: Int, _ phase: LiveTelemetryState.Phase = .loaded) -> RecordingSessionActivityContent {
        RecordingSessionActivityContent(
            telemetry: RecordingSessionActivityTestSupport.state(phase, receivedCount: count),
            vehicleName: "BRZ", startedAt: base, vehiclePhotoFileName: nil
        )
    }

    /// 最短間隔は3秒です。
    ///
    /// 責務: 公開定数が仕様の3秒であることを確認します。
    func testMinimumIntervalIsThreeSeconds() {
        XCTAssertEqual(RecordingSessionActivityUpdateThrottle.minimumInterval, 3)
    }

    /// 初回は送ります。
    ///
    /// 責務: 前回送信が無い時に送ることを確認します。
    func testFirstIsSent() {
        var throttle = RecordingSessionActivityUpdateThrottle()
        XCTAssertTrue(throttle.admit(content(0), at: base))
    }

    /// 2.999秒は送りません。
    ///
    /// 責務: 間隔未満の境界を確認します。
    func testJustBeforeIntervalIsNotSent() {
        var throttle = RecordingSessionActivityUpdateThrottle()
        _ = throttle.admit(content(0), at: base)
        XCTAssertFalse(throttle.admit(content(1), at: base.addingTimeInterval(2.999)))
    }

    /// ちょうど3秒は送ります。
    ///
    /// 責務: 間隔ちょうどの境界を確認します。
    func testExactlyIntervalIsSent() {
        var throttle = RecordingSessionActivityUpdateThrottle()
        _ = throttle.admit(content(0), at: base)
        XCTAssertTrue(throttle.admit(content(1), at: base.addingTimeInterval(3)))
    }

    /// 3.001秒は送ります。
    ///
    /// 責務: 間隔超過の境界を確認します。
    func testJustAfterIntervalIsSent() {
        var throttle = RecordingSessionActivityUpdateThrottle()
        _ = throttle.admit(content(0), at: base)
        XCTAssertTrue(throttle.admit(content(1), at: base.addingTimeInterval(3.001)))
    }

    /// 内容が前回と同じなら3秒を過ぎても送りません。
    ///
    /// 責務: 同一内容の抑止を確認します。
    func testIdenticalContentIsNotSentEvenAfterInterval() {
        var throttle = RecordingSessionActivityUpdateThrottle()
        _ = throttle.admit(content(5), at: base)
        XCTAssertFalse(throttle.admit(content(5), at: base.addingTimeInterval(10)))
    }

    /// 状態の文言キーが変われば3秒未満でも送ります。
    ///
    /// 責務: 状態キー変化の即時送信を確認します。
    func testStatusKeyChangeIsSentImmediately() {
        var throttle = RecordingSessionActivityUpdateThrottle()
        _ = throttle.admit(content(0, .loaded), at: base)
        XCTAssertTrue(throttle.admit(content(0, .failed), at: base.addingTimeInterval(0.1)))
    }

    /// 送らなかった内容は前回送信として記録しません。
    ///
    /// 責務: 拒否後も基準が最後に送った時刻のままであることを確認します。
    func testRejectedDoesNotMoveBaseline() {
        var throttle = RecordingSessionActivityUpdateThrottle()
        _ = throttle.admit(content(0), at: base)
        XCTAssertFalse(throttle.admit(content(1), at: base.addingTimeInterval(2)))
        XCTAssertTrue(throttle.admit(content(2), at: base.addingTimeInterval(3)))
    }

    /// 送った時刻が新しい基準になります。
    ///
    /// 責務: 送信後の次の判定が新しい時刻から数えられることを確認します。
    func testAdmittedMovesBaseline() {
        var throttle = RecordingSessionActivityUpdateThrottle()
        _ = throttle.admit(content(0), at: base)
        _ = throttle.admit(content(1), at: base.addingTimeInterval(3))
        XCTAssertFalse(throttle.admit(content(2), at: base.addingTimeInterval(5.999)))
        XCTAssertTrue(throttle.admit(content(2), at: base.addingTimeInterval(6)))
    }

    /// 判定だけの `shouldSend` は状態を変えません。
    ///
    /// 責務: shouldSend を繰り返しても結果が変わらないことを確認します。
    func testShouldSendDoesNotMutate() {
        var throttle = RecordingSessionActivityUpdateThrottle()
        XCTAssertTrue(throttle.shouldSend(content(0), at: base))
        XCTAssertTrue(throttle.shouldSend(content(0), at: base))
        _ = throttle.admit(content(0), at: base)
        XCTAssertFalse(throttle.shouldSend(content(1), at: base.addingTimeInterval(1)))
    }
}
