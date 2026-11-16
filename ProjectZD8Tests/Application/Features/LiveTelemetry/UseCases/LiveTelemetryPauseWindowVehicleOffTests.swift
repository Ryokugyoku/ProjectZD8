import XCTest
@testable import ProjectZD8

/// `LiveTelemetryPauseWindow.suspectVehicleOff()` が期限と判定に反映されることを検証します。
final class LiveTelemetryPauseWindowVehicleOffTests: XCTestCase {
    /// 猶予の3分です(ナノ秒)。
    private let grace: UInt64 = 180 * 1_000_000_000
    /// 最後の受信の単調時計の値です。
    private let lastReceived: UInt64 = 1_000
    /// 一時停止に入った時点です。最後の受信から5秒後です。
    private let pausedAt: UInt64 = 1_000 + 5_000_000_000

    /// 疑う前は従来どおり、期限は最後の受信+3分+1nsで、30秒では続行です。
    ///
    /// 責務: 疑いなしの `deadlineNanoseconds` と `decision` を確認します。
    func testBeforeSuspicionUsesThreeMinuteGrace() {
        let window = makeWindow(delay: .seconds30)

        XCTAssertEqual(window.deadlineNanoseconds, lastReceived + grace + 1)
        XCTAssertEqual(window.decision(nowNanoseconds: lastReceived + 30_000_000_000), .continueWaiting)
        XCTAssertFalse(window.grace.isVehicleOffSuspected)
    }

    /// 疑った後は、期限が最後の受信+設定秒数になり、その1ns前は続行、ちょうどで終了です。
    ///
    /// 責務: 設定ごとに `deadlineNanoseconds` と `decision` が疑いを反映することを確認します。
    func testAfterSuspicionDeadlineAndDecisionUseDelay() {
        for delay in VehicleOffDetectionDelay.allCases {
            var window = makeWindow(delay: delay)

            window.suspectVehicleOff()

            let deadline = lastReceived + delay.nanoseconds
            XCTAssertTrue(window.grace.isVehicleOffSuspected, "\(delay)")
            XCTAssertEqual(window.deadlineNanoseconds, deadline, "\(delay)")
            XCTAssertEqual(window.decision(nowNanoseconds: deadline - 1), .continueWaiting, "\(delay)")
            XCTAssertEqual(window.decision(nowNanoseconds: deadline), .terminate, "\(delay)")
        }
    }

    /// 疑いは一時停止の開始時点と次の定期試行の時刻を変えません。
    ///
    /// 責務: `pausedAtNanoseconds` と `nextRetryNanoseconds` が疑う前後で同じことを確認します。
    func testSuspicionKeepsPauseOriginAndRetrySchedule() {
        var window = makeWindow(delay: .seconds10)
        let nextRetry = window.nextRetryNanoseconds

        window.suspectVehicleOff()

        XCTAssertEqual(window.pausedAtNanoseconds, pausedAt)
        XCTAssertEqual(window.nextRetryNanoseconds, nextRetry)
        XCTAssertEqual(nextRetry, pausedAt + AcquisitionGracePeriodPolicy.retryIntervalNanoseconds)
    }

    /// 一時停止の開始時点で設定秒数を過ぎていても、疑う前は終了せず、疑った時点で終了です。
    ///
    /// 責務: 疑いが判定へ反映される瞬間を確認します。
    func testSuspicionTurnsContinueIntoTerminate() {
        var window = makeWindow(delay: .seconds10)
        let now = lastReceived + 20_000_000_000

        XCTAssertEqual(window.decision(nowNanoseconds: now), .continueWaiting)
        window.suspectVehicleOff()

        XCTAssertEqual(window.decision(nowNanoseconds: now), .terminate)
    }

    /// 指定の設定で最後の受信が `lastReceived` の一時停止の窓を作ります。
    ///
    /// 責務: テスト用の窓を生成します。
    /// - Parameter delay: エンジン停止とみなす時間。
    /// - Returns: 一時停止の窓。
    private func makeWindow(delay: VehicleOffDetectionDelay) -> LiveTelemetryPauseWindow {
        LiveTelemetryPauseWindow(
            pausedAtNanoseconds: pausedAt,
            grace: LiveTelemetryReceiveGrace(lastReceivedNanoseconds: lastReceived, vehicleOffDelay: delay)
        )
    }
}
