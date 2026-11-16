import XCTest
@testable import ProjectZD8

/// `LiveTelemetryReceiveGrace` のエンジン停止の疑い(設定秒数での終了)を検証します。
///
/// 仕様: 疑いが無い間は従来どおり3分(+1ns)で猶予切れ。疑いがあるときは最後の受信から設定秒数ちょうどで猶予切れ(1ns前は続行)。
/// 期限は疑い無しなら最後の受信+3分+1ns、疑いありなら最後の受信+設定秒数で、桁あふれは最大値に揃えます。
final class LiveTelemetryReceiveGraceVehicleOffTests: XCTestCase {
    /// 猶予の3分です(ナノ秒)。
    private let grace: UInt64 = 180 * 1_000_000_000
    /// 最後の受信の単調時計の値です。
    private let lastReceived: UInt64 = 7_000
    /// 1秒です(ナノ秒)。
    private let second: UInt64 = 1_000_000_000

    /// 設定を省くと既定の30秒で、疑いは無い状態から始まります。
    ///
    /// 責務: `vehicleOffDelay` の既定値と `isVehicleOffSuspected` の初期値を確認します。
    func testDefaultsToThirtySecondsAndNotSuspected() {
        let receiveGrace = LiveTelemetryReceiveGrace(lastReceivedNanoseconds: lastReceived)

        XCTAssertEqual(receiveGrace.vehicleOffDelay, .seconds30)
        XCTAssertFalse(receiveGrace.isVehicleOffSuspected)
    }

    /// 指定した設定が保持され、疑いの有無とは独立です。
    ///
    /// 責務: 4つの設定で `vehicleOffDelay` が渡した値のままで、疑いが無いことを確認します。
    func testInjectedDelayIsKept() {
        for delay in VehicleOffDetectionDelay.allCases {
            let receiveGrace = LiveTelemetryReceiveGrace(lastReceivedNanoseconds: lastReceived, vehicleOffDelay: delay)

            XCTAssertEqual(receiveGrace.vehicleOffDelay, delay)
            XCTAssertFalse(receiveGrace.isVehicleOffSuspected)
        }
    }

    /// `suspectVehicleOff()` で疑いが立ち、設定と最後の受信は変わりません。
    ///
    /// 責務: 疑いの遷移と、他の値が変わらないことを確認します。
    func testSuspectVehicleOffSetsFlagOnly() {
        var receiveGrace = LiveTelemetryReceiveGrace(lastReceivedNanoseconds: lastReceived, vehicleOffDelay: .seconds60)

        receiveGrace.suspectVehicleOff()
        receiveGrace.suspectVehicleOff()

        XCTAssertTrue(receiveGrace.isVehicleOffSuspected)
        XCTAssertEqual(receiveGrace.vehicleOffDelay, .seconds60)
        XCTAssertEqual(receiveGrace.lastReceivedNanoseconds, lastReceived)
    }

    /// 疑いが無ければ、どの設定でも判定は従来の3分(ちょうどは続行、+1nsで猶予切れ)です。
    ///
    /// 責務: 設定秒数の時点では終了せず、3分の境界だけで終了することを確認します。
    func testWithoutSuspicionDecisionUsesThreeMinuteGraceForEveryDelay() {
        for delay in VehicleOffDetectionDelay.allCases {
            let receiveGrace = LiveTelemetryReceiveGrace(lastReceivedNanoseconds: lastReceived, vehicleOffDelay: delay)

            XCTAssertEqual(receiveGrace.decision(nowNanoseconds: lastReceived + delay.nanoseconds), .continueWaiting, "\(delay)")
            XCTAssertEqual(receiveGrace.decision(nowNanoseconds: lastReceived + grace), .continueWaiting, "\(delay)")
            XCTAssertEqual(receiveGrace.decision(nowNanoseconds: lastReceived + grace + 1), .terminate, "\(delay)")
        }
    }

    /// 疑いがあれば、設定秒数ちょうどで猶予切れ、その1ns前は続行です。
    ///
    /// 責務: 4つの設定それぞれで `decision` の境界を確認します。180秒では3分(続行)より早い境界になります。
    func testWithSuspicionDecisionTerminatesExactlyAtDelay() {
        let expectations: [(VehicleOffDetectionDelay, UInt64)] = [
            (.seconds10, 10), (.seconds30, 30), (.seconds60, 60), (.seconds180, 180),
        ]
        for (delay, seconds) in expectations {
            var receiveGrace = LiveTelemetryReceiveGrace(lastReceivedNanoseconds: lastReceived, vehicleOffDelay: delay)
            receiveGrace.suspectVehicleOff()
            let boundary = lastReceived + seconds * second

            XCTAssertEqual(receiveGrace.decision(nowNanoseconds: lastReceived), .continueWaiting, "\(delay)")
            XCTAssertEqual(receiveGrace.decision(nowNanoseconds: boundary - 1), .continueWaiting, "\(delay)")
            XCTAssertEqual(receiveGrace.decision(nowNanoseconds: boundary), .terminate, "\(delay)")
            XCTAssertEqual(receiveGrace.decision(nowNanoseconds: boundary + 1), .terminate, "\(delay)")
        }
    }

    /// 疑いがあっても、現在値が最後の受信より小さい(逆行)なら経過0として続行です。
    ///
    /// 責務: 疑いありの `decision` の逆行の扱いを確認します。
    func testWithSuspicionBackwardClockContinues() {
        var receiveGrace = LiveTelemetryReceiveGrace(lastReceivedNanoseconds: lastReceived, vehicleOffDelay: .seconds10)
        receiveGrace.suspectVehicleOff()

        XCTAssertEqual(receiveGrace.decision(nowNanoseconds: lastReceived - 1), .continueWaiting)
        XCTAssertEqual(receiveGrace.decision(nowNanoseconds: 0), .continueWaiting)
    }

    /// 猶予切れ(`isExpired`)は `decision` と同じ境界に従います。
    ///
    /// 責務: 疑いの有無・設定ごとに `isExpired` の境界を確認します。
    func testIsExpiredFollowsDecision() {
        var suspected = LiveTelemetryReceiveGrace(lastReceivedNanoseconds: lastReceived, vehicleOffDelay: .seconds30)
        let unsuspected = suspected
        suspected.suspectVehicleOff()
        let thirty = lastReceived + 30 * second

        XCTAssertFalse(suspected.isExpired(nowNanoseconds: thirty - 1))
        XCTAssertTrue(suspected.isExpired(nowNanoseconds: thirty))
        XCTAssertFalse(unsuspected.isExpired(nowNanoseconds: thirty))
        XCTAssertFalse(unsuspected.isExpired(nowNanoseconds: lastReceived + grace))
        XCTAssertTrue(unsuspected.isExpired(nowNanoseconds: lastReceived + grace + 1))
    }

    /// 期限は、疑い無しなら最後の受信+3分+1ns、疑いありなら最後の受信+設定秒数です。
    ///
    /// 責務: 設定ごとの `deadlineNanoseconds` を確認します(疑い無しは設定によらない)。
    func testDeadlineDependsOnSuspicionAndDelay() {
        for delay in VehicleOffDetectionDelay.allCases {
            var receiveGrace = LiveTelemetryReceiveGrace(lastReceivedNanoseconds: lastReceived, vehicleOffDelay: delay)
            XCTAssertEqual(receiveGrace.deadlineNanoseconds, lastReceived + grace + 1, "\(delay)")

            receiveGrace.suspectVehicleOff()

            XCTAssertEqual(receiveGrace.deadlineNanoseconds, lastReceived + UInt64(delay.rawValue) * second, "\(delay)")
        }
    }

    /// 期限は、猶予切れと判定される最初の値です。
    ///
    /// 責務: 期限の1ns前は続行、期限ちょうどは猶予切れであることを、疑いの有無で確認します。
    func testDeadlineIsFirstExpiredValue() {
        for suspects in [false, true] {
            var receiveGrace = LiveTelemetryReceiveGrace(lastReceivedNanoseconds: lastReceived, vehicleOffDelay: .seconds60)
            if suspects { receiveGrace.suspectVehicleOff() }
            let deadline = receiveGrace.deadlineNanoseconds

            XCTAssertEqual(receiveGrace.decision(nowNanoseconds: deadline - 1), .continueWaiting, "suspected=\(suspects)")
            XCTAssertEqual(receiveGrace.decision(nowNanoseconds: deadline), .terminate, "suspected=\(suspects)")
        }
    }

    /// 期限の計算が桁あふれする場合は最大値に揃えます。
    ///
    /// 責務: 疑いの有無の両方で `deadlineNanoseconds` が `UInt64.max` になることを確認します。
    func testDeadlineSaturatesOnOverflow() {
        var receiveGrace = LiveTelemetryReceiveGrace(lastReceivedNanoseconds: .max, vehicleOffDelay: .seconds10)
        XCTAssertEqual(receiveGrace.deadlineNanoseconds, .max)

        receiveGrace.suspectVehicleOff()

        XCTAssertEqual(receiveGrace.deadlineNanoseconds, .max)
    }

    /// 疑いの有無・設定の違いは等価性に表れます。
    ///
    /// 責務: `Equatable` が疑いと設定を区別することを確認します。
    func testEqualityDistinguishesSuspicionAndDelay() {
        let base = LiveTelemetryReceiveGrace(lastReceivedNanoseconds: lastReceived, vehicleOffDelay: .seconds30)
        var suspected = base
        suspected.suspectVehicleOff()
        let otherDelay = LiveTelemetryReceiveGrace(lastReceivedNanoseconds: lastReceived, vehicleOffDelay: .seconds60)

        XCTAssertEqual(base, LiveTelemetryReceiveGrace(lastReceivedNanoseconds: lastReceived, vehicleOffDelay: .seconds30))
        XCTAssertNotEqual(base, suspected)
        XCTAssertNotEqual(base, otherDelay)
    }
}
