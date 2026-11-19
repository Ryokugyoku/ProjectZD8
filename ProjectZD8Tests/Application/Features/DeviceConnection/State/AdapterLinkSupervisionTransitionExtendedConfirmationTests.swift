import XCTest
@testable import ProjectZD8

/// `AdapterLinkSupervisionTransition` が、確認窓(10分)を過ぎても車両確認を休止せず、5秒間隔で続けることを検証します。
///
/// 窓後の間隔は、背面でBLE送受信を途切れさせずアプリが suspend されないための値です(S1-1)。
@MainActor
final class AdapterLinkSupervisionTransitionExtendedConfirmationTests: XCTestCase {
    /// 共通の fixture です。
    private typealias F = AdapterLinkSupervisionFixtures

    /// 遷移結果の検証手段です。
    private typealias A = AdapterLinkSupervisionResultAssertions

    /// 検証対象の遷移です。
    private let transition = AdapterLinkSupervisionTransition()

    /// 窓を過ぎた後の再確認の間隔(5秒。S1-1)です。
    private let extendedInterval = Duration.seconds(5)

    /// 窓の中の確認中の状態です。窓の終了は基準時刻+10分です。
    private func probing(attemptCount: Int = 3) -> AdapterLinkSupervisionState {
        .confirmingVehicle(F.confirmation(attemptCount: attemptCount, phase: .probing))
    }

    /// 結果が休止になっていないことを検証します。
    ///
    /// 責務: 次の状態が確認中で、段階が休止でないことを確認します。
    private func assertNotPaused(_ result: AdapterLinkSupervisionTransitionResult, _ message: String = "", line: UInt = #line) {
        guard case let .confirmingVehicle(confirmation) = result.state else {
            return XCTFail("確認中でない: \(result.state) \(message)", line: line)
        }
        XCTAssertEqual(confirmation.phase, .probing, "休止した: \(message)", line: line)
    }

    /// 窓を過ぎた無応答は休止せず、確認を送った直後なら5秒後の再確認を予約します。
    ///
    /// 責務: 窓の終了ちょうど・その後・2時間後の背面で、`.scheduleVehicleConfirmation(after: 5秒)` が出ることを確認します(仕様3・S1-1)。
    func testNoResponseAfterWindowSchedulesConfirmationInFiveSeconds() {
        for seconds in [F.windowSeconds, F.windowSeconds + 1, F.windowSeconds + 7200] {
            let now = F.date(seconds)
            let conditions = F.conditions(now: now, isForeground: false, lastVehicleConfirmationSentAt: now)
            let result = transition.result(from: probing(), on: .vehicleConfirmationCompleted(.noResponse), conditions: conditions)
            assertNotPaused(result, "\(seconds)")
            XCTAssertEqual(result.effects, [.scheduleVehicleConfirmation(after: extendedInterval)], "\(seconds)")
        }
    }

    /// 窓を過ぎた無応答でも、前面で窓を取り直したあとの確認は窓後の5秒間隔を要求しません(取り直しは従来どおり)。
    ///
    /// 責務: 前面では休止せず確認が続くことを確認します(仕様3)。
    func testNoResponseAfterWindowInForegroundDoesNotPause() {
        let now = F.date(F.windowSeconds + 30)
        let conditions = F.conditions(now: now, isForeground: true, lastVehicleConfirmationSentAt: now)
        let result = transition.result(from: probing(), on: .vehicleConfirmationCompleted(.noResponse), conditions: conditions)
        assertNotPaused(result)
        XCTAssertFalse(result.effects.isEmpty)
    }

    /// 窓を過ぎた無応答で、前回の確認から5秒以上経っていれば、待たずに次の確認を送ります。
    ///
    /// 責務: 最後の確認から5秒の境界(ちょうど・1秒前)で、確認の送信と待機の使い分けを確認します(仕様3・S1-1)。
    func testNoResponseAfterWindowConfirmsImmediatelyOnceIntervalPassed() {
        let now = F.date(F.windowSeconds + 3600)
        let due = transition.result(
            from: probing(), on: .vehicleConfirmationCompleted(.noResponse),
            conditions: F.conditions(now: now, lastVehicleConfirmationSentAt: now.addingTimeInterval(-5))
        )
        assertNotPaused(due, "ちょうど5秒")
        XCTAssertEqual(due.effects, [.confirmVehicle(.adapterMaximum)])

        let early = transition.result(
            from: probing(), on: .vehicleConfirmationCompleted(.noResponse),
            conditions: F.conditions(now: now, lastVehicleConfirmationSentAt: now.addingTimeInterval(-4))
        )
        assertNotPaused(early, "4秒")
        XCTAssertEqual(early.effects, [.scheduleVehicleConfirmation(after: .seconds(1))])
    }

    /// 窓を過ぎた待ち明けは、休止せず確認を送ります。回数の上限に達していても、時間が経っていても続けます。
    ///
    /// 責務: 窓の終了後・回数上限到達・2時間後の背面で `.confirmVehicle` が出て休止しないことを確認します(仕様3)。
    func testIntervalElapsedAfterWindowConfirmsWithoutPausing() {
        let cases: [(attempts: Int, seconds: TimeInterval)] = [
            (3, F.windowSeconds), (3, F.windowSeconds + 30), (F.maximumAttempts, F.windowSeconds + 60), (1, F.windowSeconds + 7200),
        ]
        for (attempts, seconds) in cases {
            let result = transition.result(
                from: probing(attemptCount: attempts), on: .vehicleConfirmationIntervalElapsed,
                conditions: F.conditions(now: F.date(seconds), isForeground: false)
            )
            assertNotPaused(result, "\(attempts) \(seconds)")
            XCTAssertEqual(result.effects, [.confirmVehicle(.adapterMaximum)], "\(attempts) \(seconds)")
        }
    }

    /// 確認の失敗は無応答と同じ扱いで、窓を過ぎても休止せず5秒間隔で続けます。
    ///
    /// 責務: `vehicleConfirmationFailed` が窓の後でも再確認の予約になることを確認します(仕様3)。
    func testConfirmationFailedAfterWindowSchedulesConfirmation() {
        let now = F.date(F.windowSeconds + 90)
        let result = transition.result(
            from: probing(), on: .vehicleConfirmationFailed, conditions: F.conditions(now: now, lastVehicleConfirmationSentAt: now)
        )
        assertNotPaused(result)
        XCTAssertEqual(result.effects, [.scheduleVehicleConfirmation(after: extendedInterval)])
    }

    /// 窓を過ぎても、リンクが `ready` でない・リンク未開始・手動接続が使用中なら、確認を始めも予約もしません。
    ///
    /// 責務: 各条件で、窓後の無応答と待ち明けが確認・予約の作用を出さないことを確認します(仕様5)。
    func testNoConfirmationAfterWindowWhenBlocked() {
        let now = F.date(F.windowSeconds + 30)
        var blocked: [AdapterLinkSupervisionConditions] = []
        for isForeground in [false, true] {
            blocked += [
                F.conditions(linkState: .connecting, now: now, isForeground: isForeground, lastVehicleConfirmationSentAt: now),
                F.conditions(linkPreference: nil, now: now, isForeground: isForeground, lastVehicleConfirmationSentAt: now),
                F.conditions(now: now, isExternalAdapterUseActive: true, isForeground: isForeground, lastVehicleConfirmationSentAt: now),
            ]
        }
        let events: [AdapterLinkSupervisionEvent] = [.vehicleConfirmationCompleted(.noResponse), .vehicleConfirmationIntervalElapsed]
        for conditions in blocked {
            for event in events {
                let result = transition.result(from: probing(), on: event, conditions: conditions)
                let started = result.effects.contains {
                    if case .confirmVehicle = $0 { true } else if case .scheduleVehicleConfirmation = $0 { true } else { false }
                }
                XCTAssertFalse(started, "\(event) \(conditions) \(result.effects)")
            }
        }
    }

    /// 窓の中の確認は、従来どおり窓の終了までは休止せず続きます。
    ///
    /// 責務: 窓の終了の直前(1ミリ秒前)の待ち明けで確認を送ることを確認します(窓内は従来どおり)。
    func testIntervalElapsedJustBeforeWindowEndConfirms() {
        let result = transition.result(
            from: probing(), on: .vehicleConfirmationIntervalElapsed, conditions: F.conditions(now: F.date(F.windowSeconds - 0.001))
        )
        A.assertResult(
            result, state: .confirmingVehicle(F.confirmation(attemptCount: 4, phase: .probing)), effects: [.confirmVehicle(.adapterMaximum)]
        )
    }
}
