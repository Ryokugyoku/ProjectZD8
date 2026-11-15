import Foundation
import XCTest
@testable import ProjectZD8

/// 最後の正応答の追跡と、途絶(応答途絶・リンク断)の判定を検証します。
final class LiveTelemetryReceiveTrackerTests: XCTestCase {
    /// 途絶閾値です。
    private let threshold = AcquisitionStallPolicy.stallThresholdNanoseconds

    /// 開始時点から途絶閾値未満は途絶なし、ちょうど閾値で応答途絶です。
    ///
    /// 責務: 開始時刻を起点にした閾値の境界を確認します。
    func testStallBoundaryFromStart() {
        let tracker = LiveTelemetryReceiveTracker(startedNanoseconds: 100, startedAt: date(1))

        XCTAssertNil(tracker.interruption(nowNanoseconds: 100 + threshold - 1))
        XCTAssertEqual(tracker.interruption(nowNanoseconds: 100 + threshold), .responseStall)
        XCTAssertEqual(tracker.lastReceivedAt, date(1))
    }

    /// 正応答は最後の受信を更新し、非応答の結果は更新しません。
    ///
    /// 責務: 正応答とタイムアウト・非対応・未分類・取消の観測で、起点と実時刻の扱いを確認します。
    func testRespondedUpdatesLastReceiveOthersDoNot() {
        var tracker = LiveTelemetryReceiveTracker(startedNanoseconds: 0, startedAt: date(1))
        tracker.observe(.responded([1]), atNanoseconds: 1_000, at: date(2))
        for outcome in [OBDPIDRequestTransportOutcome.timedOut, .unsupported, .unclassifiedResponse, .cancelled] {
            tracker.observe(outcome, atNanoseconds: 9_000_000_000, at: date(9))
        }

        XCTAssertEqual(tracker.lastReceivedNanoseconds, 1_000)
        XCTAssertEqual(tracker.lastReceivedAt, date(2))
        XCTAssertNil(tracker.interruption(nowNanoseconds: 1_000 + threshold - 1))
        XCTAssertEqual(tracker.interruption(nowNanoseconds: 1_000 + threshold), .responseStall)
    }

    /// 通信失敗は経過にかかわらずリンク断で、その後の正応答で消えます。
    ///
    /// 責務: リンク断の観測と、正応答による解除を確認します。
    func testTransportFailureIsLinkLostUntilNextResponse() {
        var tracker = LiveTelemetryReceiveTracker(startedNanoseconds: 0, startedAt: date(1))
        tracker.observe(.transportFailure, atNanoseconds: 1, at: date(1))
        XCTAssertEqual(tracker.interruption(nowNanoseconds: 1), .linkLost)

        tracker.observe(.responded([1]), atNanoseconds: 2, at: date(2))

        XCTAssertNil(tracker.interruption(nowNanoseconds: 2))
    }

    /// 単調時計や実時刻が戻った観測では最後の受信を戻さず、現在が最後の受信より前なら経過0です。
    ///
    /// 責務: 逆行の扱いを確認します。
    func testBackwardClockDoesNotRewindOrStall() {
        var tracker = LiveTelemetryReceiveTracker(startedNanoseconds: 0, startedAt: date(1))
        tracker.observe(.responded([1]), atNanoseconds: threshold * 2, at: date(5))
        tracker.observe(.responded([1]), atNanoseconds: 10, at: date(3))

        XCTAssertEqual(tracker.lastReceivedNanoseconds, threshold * 2)
        XCTAssertEqual(tracker.lastReceivedAt, date(5))
        XCTAssertNil(tracker.interruption(nowNanoseconds: 0))
    }

    /// 再開は起点を置き換え、リンク断の観測を消します。
    ///
    /// 責務: `restart` が逆行も含めて起点を置き換えることを確認します。
    func testRestartReplacesBaseline() {
        var tracker = LiveTelemetryReceiveTracker(startedNanoseconds: 500, startedAt: date(5))
        tracker.observe(.transportFailure, atNanoseconds: 600, at: date(6))

        tracker.restart(atNanoseconds: 50, at: date(2))

        XCTAssertEqual(tracker.lastReceivedNanoseconds, 50)
        XCTAssertEqual(tracker.lastReceivedAt, date(2))
        XCTAssertFalse(tracker.observedLinkLoss)
        XCTAssertEqual(tracker.interruption(nowNanoseconds: 50 + threshold), .responseStall)
    }

    /// 指定秒の日時を返します。
    ///
    /// 責務: 1970年起点の秒を日時へ変換します。
    /// - Parameter seconds: 秒。
    /// - Returns: 日時。
    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }
}
