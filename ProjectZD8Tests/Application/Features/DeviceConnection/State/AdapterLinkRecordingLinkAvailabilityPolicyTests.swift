import XCTest
@testable import ProjectZD8

/// `AdapterLinkRecordingLinkAvailabilityPolicy` が、記録中の常駐リンクの `ready` への出入りだけを可用性の変化として返すことを検証します。
///
/// 仕様(U2 受け入れ条件 4): 監視が記録中の間、常駐リンクが `ready` になったらリンク復帰、`ready` でなくなったらリンク断を取得側へ届けます。
@MainActor
final class AdapterLinkRecordingLinkAvailabilityPolicyTests: XCTestCase {
    /// 共通の fixture です。
    private typealias F = AdapterLinkSupervisionFixtures

    /// 検証対象の方針です。
    private let policy = AdapterLinkRecordingLinkAvailabilityPolicy()

    /// 記録中の状態です。
    private let recording = AdapterLinkSupervisionState.recording(AdapterLinkSupervisionFixtures.detectedVehicle)

    /// `ready` 以外の全リンク状態です。
    private let nonReady: [AdapterLinkState] = [
        .idle, .awaitingPeripheral, .connecting, .discovering,
        .disconnected(.peripheralDisconnected(errorDescription: nil)), .disconnected(.retryLimitExceeded),
    ]

    /// 記録中に `ready` から `ready` 以外へ変わったらリンク断(`false`)です。
    ///
    /// 責務: 全ての非 `ready` 状態への変化で `false` を返すことを確認します。
    func testReadyToNonReadyWhileRecordingIsLinkLoss() {
        for linkState in nonReady {
            XCTAssertEqual(change(to: linkState, from: recording, previous: .ready), false, "\(linkState)")
        }
    }

    /// 記録中に `ready` 以外から `ready` へ変わったらリンク復帰(`true`)です。
    ///
    /// 責務: 全ての非 `ready` 状態からの変化で `true` を返すことを確認します。
    func testNonReadyToReadyWhileRecordingIsLinkRestored() {
        for previous in nonReady {
            XCTAssertEqual(change(to: .ready, from: recording, previous: previous), true, "\(previous)")
        }
    }

    /// `ready` の出入りが無い変化(`ready` の再通知、非 `ready` どうし)は伝えません。
    ///
    /// 責務: 境界として、同じ側にとどまる変化で `nil` を返すことを確認します。
    func testChangesWithoutCrossingReadyAreIgnored() {
        XCTAssertNil(change(to: .ready, from: recording, previous: .ready))
        for previous in nonReady {
            for linkState in nonReady {
                XCTAssertNil(change(to: linkState, from: recording, previous: previous), "\(previous) → \(linkState)")
            }
        }
    }

    /// 記録中以外の状態では、`ready` の出入りがあっても伝えません。
    ///
    /// 責務: 記録中以外の全状態(抑止中を含む)で `nil` を返すことを確認します。
    func testOutsideRecordingIsIgnored() {
        let states = F.allStates.filter { if case .recording = $0 { false } else { true } } + [.heldAfterUserStop]
        for state in states {
            XCTAssertNil(change(to: .connecting, from: state, previous: .ready), "\(state)")
            XCTAssertNil(change(to: .ready, from: state, previous: .connecting), "\(state)")
        }
    }

    /// リンクを開始していなければ、記録中でも伝えません。
    ///
    /// 責務: `linkPreference` が無い条件で `nil` を返すことを確認します。
    func testWithoutStartedLinkIsIgnored() {
        let conditions = F.conditions(linkPreference: nil, linkState: .ready)
        XCTAssertNil(policy.availabilityChange(on: .linkStateChanged(.connecting), from: recording, conditions: conditions))
    }

    /// リンク状態の変化以外のイベントでは伝えません。
    ///
    /// 責務: 記録中に届く他のイベントで `nil` を返すことを確認します。
    func testOtherEventsAreIgnored() {
        let events: [AdapterLinkSupervisionEvent] = [
            .operatingConditionsChanged, .appDidBecomeActive, .recordingDidFinish(endReason: .connectionLost),
            .externalAdapterUseBegan, .externalAdapterUseEnded, .finishingDidComplete,
        ]
        for event in events {
            XCTAssertNil(policy.availabilityChange(on: event, from: recording, conditions: F.conditions(linkState: .connecting)), "\(event)")
        }
    }

    /// 1件のリンク状態の変化を評価します。
    ///
    /// 責務: 直前のリンク状態を条件に入れて方針を呼びます。
    /// - Parameters:
    ///   - linkState: 変化後のリンク状態。
    ///   - state: 監視状態。
    ///   - previous: 直前のリンク状態。
    /// - Returns: 方針の判定。
    private func change(to linkState: AdapterLinkState, from state: AdapterLinkSupervisionState, previous: AdapterLinkState) -> Bool? {
        policy.availabilityChange(on: .linkStateChanged(linkState), from: state, conditions: F.conditions(linkState: previous))
    }
}
