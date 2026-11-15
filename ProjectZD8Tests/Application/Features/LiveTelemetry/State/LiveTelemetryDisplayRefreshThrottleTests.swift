import Foundation
import XCTest
@testable import ProjectZD8

/// 表示更新の間引きが、最小間隔と保留中の観測を仕様どおりに扱うことを検証します。
final class LiveTelemetryDisplayRefreshThrottleTests: XCTestCase {
    /// 最小間隔のナノ秒です。
    private let interval = LiveTelemetryDisplayRefreshThrottle.minimumIntervalNanoseconds

    /// 最小間隔は250ミリ秒です。
    ///
    /// 責務: 表示更新の最小間隔の値を確認します。
    func testMinimumIntervalIs250Milliseconds() {
        XCTAssertEqual(interval, 250_000_000)
    }

    /// 保留が空なら、初回でも間隔経過後でも返しません。
    ///
    /// 責務: 観測が無いときに表示更新を起こさないことを確認します。
    func testEmptyPendingReturnsNil() {
        var throttle = LiveTelemetryDisplayRefreshThrottle()
        XCTAssertNil(throttle.takeIfDue(nowNanoseconds: 0))
        throttle.hold(sample(1))
        _ = throttle.takeIfDue(nowNanoseconds: 10)

        XCTAssertNil(throttle.takeIfDue(nowNanoseconds: 10 + interval * 2))
    }

    /// 最初の観測は経過を待たずに返します。
    ///
    /// 責務: まだ一度も更新していない状態で即座に反映することを確認します。
    func testFirstSampleIsReturnedImmediately() {
        var throttle = LiveTelemetryDisplayRefreshThrottle()
        throttle.hold(sample(1))

        XCTAssertEqual(throttle.takeIfDue(nowNanoseconds: 5), [sample(1)])
        XCTAssertEqual(throttle.pendingSamples, [])
    }

    /// 最小間隔未満は返さず、ちょうど最小間隔で保留中の観測を受信順にまとめて返します。
    ///
    /// 責務: 間隔の境界(1ナノ秒前とちょうど)と、間引いた観測を捨てないことを確認します。
    func testSamplesAreHeldUntilExactlyMinimumInterval() {
        var throttle = LiveTelemetryDisplayRefreshThrottle()
        throttle.hold(sample(1))
        _ = throttle.takeIfDue(nowNanoseconds: 1_000)
        throttle.hold(sample(2))
        throttle.hold(sample(3))

        XCTAssertNil(throttle.takeIfDue(nowNanoseconds: 1_000))
        XCTAssertNil(throttle.takeIfDue(nowNanoseconds: 1_000 + interval - 1))
        XCTAssertEqual(throttle.pendingSamples, [sample(2), sample(3)])
        XCTAssertEqual(throttle.takeIfDue(nowNanoseconds: 1_000 + interval), [sample(2), sample(3)])
        XCTAssertEqual(throttle.pendingSamples, [])
    }

    /// 次の更新は、直前に返した時刻から最小間隔で測ります。
    ///
    /// 責務: 反映した時刻を次の間隔の起点にすることを確認します。
    func testIntervalRestartsFromLastRefresh() {
        var throttle = LiveTelemetryDisplayRefreshThrottle()
        throttle.hold(sample(1))
        _ = throttle.takeIfDue(nowNanoseconds: 0)
        throttle.hold(sample(2))
        _ = throttle.takeIfDue(nowNanoseconds: interval + 10)
        throttle.hold(sample(3))

        XCTAssertNil(throttle.takeIfDue(nowNanoseconds: interval * 2 + 9))
        XCTAssertEqual(throttle.takeIfDue(nowNanoseconds: interval * 2 + 10), [sample(3)])
    }

    /// `takeAll` は間隔にかかわらず保留中の観測をすべて返し、空なら空配列を返します。
    ///
    /// 責務: フェーズ変化用の強制反映が間引かれないことを確認します。
    func testTakeAllReturnsRegardlessOfInterval() {
        var throttle = LiveTelemetryDisplayRefreshThrottle()
        throttle.hold(sample(1))
        _ = throttle.takeIfDue(nowNanoseconds: 100)
        throttle.hold(sample(2))
        throttle.hold(sample(3))

        XCTAssertEqual(throttle.takeAll(nowNanoseconds: 101), [sample(2), sample(3)])
        XCTAssertEqual(throttle.takeAll(nowNanoseconds: 102), [])
    }

    /// 時計が前回の更新より逆行した入力では反映しません。
    ///
    /// 責務: 逆行した時刻を経過とみなさず、観測を保留したままにすることを確認します。
    func testBackwardClockDoesNotRefresh() {
        var throttle = LiveTelemetryDisplayRefreshThrottle()
        throttle.hold(sample(1))
        _ = throttle.takeIfDue(nowNanoseconds: interval * 4)
        throttle.hold(sample(2))

        XCTAssertNil(throttle.takeIfDue(nowNanoseconds: interval))
        XCTAssertNil(throttle.takeIfDue(nowNanoseconds: 0))
        XCTAssertEqual(throttle.pendingSamples, [sample(2)])
    }

    /// テスト用の観測を生成します。
    ///
    /// 責務: 値だけが異なる回転数の観測を返します。
    /// - Parameter value: 観測値。
    /// - Returns: 観測。
    private func sample(_ value: Double) -> OBDPIDSample {
        OBDPIDSample(
            request: OBDPIDRequest(service: 0x01, pid: 0x0C), nameKey: "test.rpm", value: value, unit: "rpm",
            vehicleModelCode: nil, observedAt: Date(timeIntervalSince1970: value), summaryKey: "s",
            highValueKey: "h", lowValueKey: "l", correlationKey: "c"
        )
    }
}
