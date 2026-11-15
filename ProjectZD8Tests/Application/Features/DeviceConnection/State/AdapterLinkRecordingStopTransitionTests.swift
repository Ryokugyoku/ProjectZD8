import XCTest
@testable import ProjectZD8

/// `AdapterLinkRecordingStopTransition` が、稼働条件の喪失・接続の置き換え・監視の停止で、全状態を仕様どおりに巻き戻すことを検証します。
@MainActor
final class AdapterLinkRecordingStopTransitionTests: XCTestCase {
    /// 共通の fixture です。
    private typealias F = AdapterLinkSupervisionFixtures
    /// 遷移結果の検証手段です。
    private typealias A = AdapterLinkSupervisionResultAssertions

    /// 検証対象の遷移です。
    private let transition = AdapterLinkRecordingStopTransition()

    /// すべての停止理由です。
    private let reasons: [AdapterLinkRecordingStopReason] = [.accountSignedOut, .superseded, .connectionTargetLost, .supervisionStopped]

    /// 記録中は、渡した理由そのままで停止を要求して終了へ移り、取り消しと通知の取り下げを行います。
    ///
    /// 責務: 理由ごとに `.finishing` と `[.cancelOperations, .dismissNotification, .requestRecordingStop(理由)]` になることを確認します(仕様 9〜12)。
    func testRecordingRequestsStopWithGivenReason() {
        for reason in reasons {
            let result = transition.stopped(from: .recording(F.detectedVehicle), reason: reason)
            A.assertResult(result, state: .finishing, effects: [.cancelOperations, .dismissNotification, .requestRecordingStop(reason)], "\(reason)")
        }
    }

    /// 終了中は、停止要求を重ねずに終了のままです。
    ///
    /// 責務: 理由ごとに `.finishing` と取り消し・通知の取り下げだけになることを確認します。
    func testFinishingStaysFinishingWithoutSecondStop() {
        for reason in reasons {
            let result = transition.stopped(from: .finishing, reason: reason)
            A.assertResult(result, state: .finishing, effects: [.cancelOperations, .dismissNotification], "\(reason)")
        }
    }

    /// 記録中・終了中以外(抑止中を含む)は、停止要求なしで待機へ戻ります。
    ///
    /// 責務: 残りの全状態と全理由で `.standby` と取り消し・通知の取り下げだけになることを確認します(仕様 12)。
    func testOtherStatesReturnToStandbyWithoutStop() {
        let others = F.allStates.filter { state in
            if case .recording = state { return false }
            return state != .finishing
        } + [.heldAfterUserStop]
        XCTAssertEqual(others.count, 7)
        for state in others {
            for reason in reasons {
                let result = transition.stopped(from: state, reason: reason)
                A.assertResult(result, state: .standby, effects: [.cancelOperations, .dismissNotification], "\(state) \(reason)")
            }
        }
    }
}
