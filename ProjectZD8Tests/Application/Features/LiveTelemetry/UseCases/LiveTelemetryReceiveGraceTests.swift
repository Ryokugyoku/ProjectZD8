import XCTest
@testable import ProjectZD8

/// 最後の正応答の受信を起点にした猶予の判定・猶予切れ・期限を検証します。
///
/// 仕様: 経過が猶予(3分)以下なら続行、超えたら猶予切れ。現在値が起点より小さい場合は経過0とします。
/// 期限は猶予切れと判定される最初の値(最後の受信 + 猶予 + 1ナノ秒)で、桁あふれは最大値に揃えます。
final class LiveTelemetryReceiveGraceTests: XCTestCase {
    /// 猶予の3分です(ナノ秒)。
    private let grace: UInt64 = 180 * 1_000_000_000
    /// 最後の受信の単調時計の値です。
    private let lastReceived: UInt64 = 7_000

    /// 最後の受信からちょうど猶予とその直前・経過0は続行、直後は猶予切れです。
    ///
    /// 責務: `decision` の境界値を確認します。
    func testDecisionBoundaries() {
        let receiveGrace = LiveTelemetryReceiveGrace(lastReceivedNanoseconds: lastReceived)

        XCTAssertEqual(receiveGrace.decision(nowNanoseconds: lastReceived), .continueWaiting)
        XCTAssertEqual(receiveGrace.decision(nowNanoseconds: lastReceived + grace - 1), .continueWaiting)
        XCTAssertEqual(receiveGrace.decision(nowNanoseconds: lastReceived + grace), .continueWaiting)
        XCTAssertEqual(receiveGrace.decision(nowNanoseconds: lastReceived + grace + 1), .terminate)
    }

    /// 現在値が最後の受信より小さい(逆行)場合は経過0として続行です。
    ///
    /// 責務: `decision` の逆行の扱いを確認します。
    func testDecisionTreatsBackwardClockAsZeroElapsed() {
        let receiveGrace = LiveTelemetryReceiveGrace(lastReceivedNanoseconds: lastReceived)

        XCTAssertEqual(receiveGrace.decision(nowNanoseconds: lastReceived - 1), .continueWaiting)
        XCTAssertEqual(receiveGrace.decision(nowNanoseconds: 0), .continueWaiting)
    }

    /// 猶予切れは最後の受信から猶予を超えたときだけ真です。
    ///
    /// 責務: `isExpired` の境界値と逆行を確認します。
    func testIsExpiredBoundaries() {
        let receiveGrace = LiveTelemetryReceiveGrace(lastReceivedNanoseconds: lastReceived)

        XCTAssertFalse(receiveGrace.isExpired(nowNanoseconds: 0))
        XCTAssertFalse(receiveGrace.isExpired(nowNanoseconds: lastReceived))
        XCTAssertFalse(receiveGrace.isExpired(nowNanoseconds: lastReceived + grace - 1))
        XCTAssertFalse(receiveGrace.isExpired(nowNanoseconds: lastReceived + grace))
        XCTAssertTrue(receiveGrace.isExpired(nowNanoseconds: lastReceived + grace + 1))
    }

    /// 期限は最後の受信 + 猶予 + 1ナノ秒で、桁あふれは最大値です。
    ///
    /// 責務: `deadlineNanoseconds` の値と桁あふれ(ちょうど最大値に届く場合を含む)を確認します。
    func testDeadlineIsFirstExpiredValue() {
        XCTAssertEqual(LiveTelemetryReceiveGrace(lastReceivedNanoseconds: lastReceived).deadlineNanoseconds, lastReceived + grace + 1)
        XCTAssertEqual(LiveTelemetryReceiveGrace(lastReceivedNanoseconds: 0).deadlineNanoseconds, grace + 1)
        XCTAssertEqual(LiveTelemetryReceiveGrace(lastReceivedNanoseconds: .max - grace - 1).deadlineNanoseconds, .max)
        XCTAssertEqual(LiveTelemetryReceiveGrace(lastReceivedNanoseconds: .max - 5).deadlineNanoseconds, .max)
    }

    /// 期限の値では猶予切れで、その1ナノ秒前では猶予内です。
    ///
    /// 責務: `deadlineNanoseconds` と `isExpired` の整合を、起点を変えて確認します。
    func testDeadlineAgreesWithIsExpired() {
        for origin: UInt64 in [0, lastReceived, 3_000_000_000] {
            let receiveGrace = LiveTelemetryReceiveGrace(lastReceivedNanoseconds: origin)

            XCTAssertTrue(receiveGrace.isExpired(nowNanoseconds: receiveGrace.deadlineNanoseconds), "\(origin)")
            XCTAssertFalse(receiveGrace.isExpired(nowNanoseconds: receiveGrace.deadlineNanoseconds - 1), "\(origin)")
        }
    }
}
