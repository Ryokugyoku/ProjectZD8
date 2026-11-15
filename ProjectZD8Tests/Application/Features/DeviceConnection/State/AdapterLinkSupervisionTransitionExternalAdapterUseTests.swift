import XCTest
@testable import ProjectZD8

/// `AdapterLinkSupervisionTransition` が手動使用の入力を振り分け、抑止中(`isExternalAdapterUseActive`)は
/// 初期化・車両確認を始めず、それ以外の遷移を従来どおりに保つことを検証します。
@MainActor
final class AdapterLinkSupervisionTransitionExternalAdapterUseTests: XCTestCase {
    /// 共通の fixture です。
    private typealias F = AdapterLinkSupervisionFixtures

    /// 遷移結果の検証手段です。
    private typealias A = AdapterLinkSupervisionResultAssertions

    /// 検証対象の遷移です。
    private let transition = AdapterLinkSupervisionTransition()

    /// 指定の条件を、手動使用の抑止の有無だけ変えて作り直します。
    ///
    /// 責務: fixture の条件へ `isExternalAdapterUseActive` を設定します。
    /// - Parameters:
    ///   - conditions: 元の条件。
    ///   - isActive: 手動使用中かどうか。
    /// - Returns: 抑止の有無だけが違う条件。
    private func conditions(_ conditions: AdapterLinkSupervisionConditions, suppressed isActive: Bool) -> AdapterLinkSupervisionConditions {
        AdapterLinkSupervisionConditions(
            isSupervisionStarted: conditions.isSupervisionStarted,
            isSignedIn: conditions.isSignedIn,
            defaultAdapterPreference: conditions.defaultAdapterPreference,
            linkPreference: conditions.linkPreference,
            linkState: conditions.linkState,
            now: conditions.now,
            isExternalAdapterUseActive: isActive
        )
    }

    /// 条件の既定値は「抑止なし」です。
    ///
    /// 責務: 抑止の引数を省いた条件が手動使用中でないことを確認します。
    func testConditionsDefaultToNotSuppressed() {
        XCTAssertFalse(F.conditions().isExternalAdapterUseActive)
        XCTAssertTrue(conditions(F.conditions(), suppressed: true).isExternalAdapterUseActive)
    }

    /// 手動使用の開始・終了イベントは、全状態で専用の遷移と同じ結果になります。
    ///
    /// 責務: 振り分けが `AdapterLinkExternalAdapterUseTransition` の結果を返すことを確認します。
    func testExternalAdapterUseEventsAreRouted() {
        let external = AdapterLinkExternalAdapterUseTransition()
        for state in F.allStates {
            for isActive in [false, true] {
                let current = conditions(F.conditions(), suppressed: isActive)
                XCTAssertEqual(transition.result(from: state, on: .externalAdapterUseBegan, conditions: current), external.began(from: state))
                XCTAssertEqual(transition.result(from: state, on: .externalAdapterUseEnded, conditions: current), external.ended(from: state))
            }
        }
    }

    /// 抑止中はリンクが `ready` になっても初期化を始めません。抑止していなければ初期化を始めます。
    ///
    /// 責務: 待機・直前が非 ready の `ready` 通知で、抑止の有無による違いを確認します。
    func testLinkReadyDoesNotInitializeWhileSuppressed() {
        let base = F.conditions(linkState: .connecting)

        let suppressed = transition.result(from: .standby, on: .linkStateChanged(.ready), conditions: conditions(base, suppressed: true))
        A.assertIgnored(suppressed, from: .standby)

        let normal = transition.result(from: .standby, on: .linkStateChanged(.ready), conditions: conditions(base, suppressed: false))
        A.assertResult(normal, state: .initializing(linkReadyAt: F.referenceDate), effects: [.initializeAdapter])
    }

    /// 抑止中はアプリが前面へ戻っても、どの状態でも初期化・車両確認を始めず、通知も出しません。
    ///
    /// 責務: 全状態で状態不変・作用なしになり、抑止していなければ待機から初期化・休止から確認が始まることを確認します。
    func testAppDidBecomeActiveIsIgnoredWhileSuppressed() {
        for state in F.allStates {
            let result = transition.result(from: state, on: .appDidBecomeActive, conditions: conditions(F.conditions(), suppressed: true))
            A.assertIgnored(result, from: state, "\(state)")
        }
        let normal = conditions(F.conditions(), suppressed: false)
        let standby = transition.result(from: .standby, on: .appDidBecomeActive, conditions: normal)
        A.assertResult(standby, state: .initializing(linkReadyAt: F.referenceDate), effects: [.initializeAdapter])
        let paused = transition.result(from: .confirmingVehicle(F.confirmation(phase: .paused)), on: .appDidBecomeActive, conditions: normal)
        XCTAssertTrue(paused.effects.contains(.confirmVehicle(.adapterMaximum)))
    }

    /// サインアウト・既定アダプターの削除・監視停止・リンク断・記録終了は、抑止中でも従来どおりに働きます。
    ///
    /// 責務: これらの入力の結果が、全状態で抑止の有無によって変わらないことを確認します。
    func testOtherInputsBehaveTheSameWhileSuppressed() {
        let cases: [(AdapterLinkSupervisionEvent, AdapterLinkSupervisionConditions)] = [
            (.operatingConditionsChanged, F.conditions(isSignedIn: false)),
            (.operatingConditionsChanged, F.conditions(defaultAdapterPreference: nil)),
            (.operatingConditionsChanged, F.conditions(isSupervisionStarted: false)),
            (.linkStateChanged(.disconnected(.peripheralDisconnected(errorDescription: nil))), F.conditions()),
            (.linkStateChanged(.connecting), F.conditions()),
            (.recordingDidFinish(endReason: nil), F.conditions()),
            (.finishingDidComplete, F.conditions()),
        ]
        for state in F.allStates {
            for (event, base) in cases {
                let suppressed = transition.result(from: state, on: event, conditions: conditions(base, suppressed: true))
                let normal = transition.result(from: state, on: event, conditions: conditions(base, suppressed: false))
                XCTAssertEqual(suppressed, normal, "\(state) \(event)")
            }
        }
    }

    /// サインアウトは抑止中でもリンクを停止します。
    ///
    /// 責務: 抑止中のサインアウトで `stopLink` が出ることを、比較ではなく直接確認します。
    func testSignOutStopsLinkWhileSuppressed() {
        let result = transition.result(
            from: .standby, on: .operatingConditionsChanged, conditions: conditions(F.conditions(isSignedIn: false), suppressed: true)
        )
        XCTAssertTrue(result.effects.contains(.stopLink))
    }

    /// 抑止中に待機で届いた古い非同期結果(初期化成功・車両確認・VIN読取)は状態を動かしません。
    ///
    /// 責務: 取り消し後の待機で、遅れて届いた結果が無視されることを確認します。
    func testStaleResultsInStandbyAreIgnoredWhileSuppressed() {
        let suppressed = conditions(F.conditions(), suppressed: true)
        let events: [AdapterLinkSupervisionEvent] = [
            .adapterInitializationSucceeded(F.evidence), .adapterInitializationFailed,
            .vehicleConfirmationCompleted(.responding), .vehicleConfirmationFailed, .vehicleConfirmationIntervalElapsed,
            .vinReadCompleted(vin: F.vin, isAutomaticRecordingEnabled: true), .vinReadFailed(isAutomaticRecordingEnabled: true),
            .recordingStartSelected,
        ]
        for event in events {
            A.assertIgnored(transition.result(from: .standby, on: event, conditions: suppressed), from: .standby, "\(event)")
        }
    }
}
