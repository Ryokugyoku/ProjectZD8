import XCTest
@testable import ProjectZD8

/// `AdapterLinkExternalAdapterUseTransition` の「手動使用が始まった/終わった」の遷移を、全状態について検証します。
@MainActor
final class AdapterLinkExternalAdapterUseTransitionTests: XCTestCase {
    /// 共通の fixture です。
    private typealias F = AdapterLinkSupervisionFixtures

    /// 検証対象の遷移です。
    private let transition = AdapterLinkExternalAdapterUseTransition()

    /// 進行中の処理を取り消して待機へ戻る状態(初期化・車両確認・検知済み)です。
    private var cancellableStates: [AdapterLinkSupervisionState] {
        F.allStates.filter { state in
            switch state {
            case .initializing, .confirmingVehicle, .vehicleDetected: true
            case .standby, .recording, .finishing, .heldAfterUserStop: false
            }
        }
    }

    /// 作用にリンク停止・初期化・確認・記録開始が含まれないことを確認します。
    ///
    /// 責務: 手動使用の入力でリンクを止めず、新しい処理を始めないことをまとめて検証します。
    /// - Parameters:
    ///   - effects: 遷移の作用。
    ///   - message: 失敗時の補足。
    private func assertNoLinkStopOrNewWork(
        _ effects: [AdapterLinkSupervisionEffect], _ message: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        for effect in effects {
            switch effect {
            case .stopLink, .startLink, .initializeAdapter, .confirmVehicle, .scheduleVehicleConfirmation, .scheduleAdapterInitializationRetry, .readVIN,
                 .presentVehicleDetected, .presentRecordingStarted, .requestRecordingStart:
                XCTFail("出してはいけない作用 \(effect): \(message)", file: file, line: line)
            case .prepareNotifications, .cancelOperations, .dismissNotification, .requestRecordingStop, .completeFinishing:
                continue
            }
        }
    }

    /// 対象の状態が初期化・車両確認(確認中・休止中)・検知済み(VIN読取中・記録開始待ち)の5つを網羅していることを確認します。
    ///
    /// 責務: fixture の変更で検証対象が欠けないことを確認します。
    func testCancellableStatesCoverEveryInProgressPhase() {
        XCTAssertEqual(cancellableStates.count, 5)
    }

    /// 初期化・車両確認・検知済みで手動使用が始まったら、処理を取り消し、通知を取り下げて待機へ戻ります。
    ///
    /// 責務: 次の状態が待機で、取り消しと通知の取り下げが出て、リンクを止めないことを確認します。
    func testBeganCancelsInProgressWorkAndReturnsToStandby() {
        for state in cancellableStates {
            let result = transition.began(from: state)
            XCTAssertEqual(result.state, .standby, "\(state)")
            XCTAssertTrue(result.effects.contains(.cancelOperations), "\(state)")
            XCTAssertTrue(result.effects.contains(.dismissNotification), "\(state)")
            XCTAssertFalse(AdapterLinkSupervisionResultAssertions.containsRecordingStopRequest(result.effects), "\(state)")
            assertNoLinkStopOrNewWork(result.effects, "\(state)")
        }
    }

    /// 記録中に手動使用が始まったら、記録の停止を要求して終了へ進みます。
    ///
    /// 責務: 次の状態が終了中で、停止要求が1回出て、リンクを止めないことを確認します。
    func testBeganWhileRecordingRequestsStopAndMovesToFinishing() {
        let result = transition.began(from: .recording(F.detectedVehicle))

        XCTAssertEqual(result.state, .finishing)
        XCTAssertEqual(result.effects.filter { $0 == .requestRecordingStop(.superseded) }.count, 1)
        XCTAssertTrue(result.effects.contains(.dismissNotification))
        assertNoLinkStopOrNewWork(result.effects, "recording")
    }

    /// 終了中に手動使用が始まっても終了のままで、停止要求を重ねません。
    ///
    /// 責務: 状態が終了中のままで、停止要求とリンク停止が出ないことを確認します。
    func testBeganWhileFinishingStaysFinishing() {
        let result = transition.began(from: .finishing)

        XCTAssertEqual(result.state, .finishing)
        XCTAssertFalse(AdapterLinkSupervisionResultAssertions.containsRecordingStopRequest(result.effects))
        assertNoLinkStopOrNewWork(result.effects, "finishing")
    }

    /// 待機中に手動使用が始まっても、状態も作用も変わりません。
    ///
    /// 責務: 待機での開始入力が何もしないことを確認します。
    func testBeganInStandbyIsIgnored() {
        AdapterLinkSupervisionResultAssertions.assertIgnored(transition.began(from: .standby), from: .standby)
    }

    /// 手動使用が終わっても、待機以外の状態は変えず作用も出しません。
    ///
    /// 責務: 待機以外の全状態で、リンクが `ready` でも状態不変・作用なしであることを確認します。
    func testEndedOutsideStandbyIsIgnored() {
        for state in F.allStates where state != .standby {
            AdapterLinkSupervisionResultAssertions.assertIgnored(
                transition.ended(from: state, conditions: F.conditions()), from: state, "\(state)"
            )
        }
    }

    /// 手動使用が終わったとき、待機でリンクが `ready` なら、すぐ初期化からやり直します。
    ///
    /// 責務: `initializing(linkReadyAt: now)` と初期化の作用になることを確認します(仕様1)。
    func testEndedInReadyStandbyReinitializes() {
        let now = F.date(321)
        let result = transition.ended(from: .standby, conditions: F.conditions(now: now))
        AdapterLinkSupervisionResultAssertions.assertResult(result, state: .initializing(linkReadyAt: now), effects: [.initializeAdapter])
    }

    /// 待機でも、リンクが `ready` でない・リンク未開始・手動接続が使用中なら何もしません。
    ///
    /// 責務: 初期化を始められない各条件で、待機のまま作用なしであることを確認します(仕様4)。
    func testEndedInStandbyIsIgnoredWhenBlocked() {
        let blocked = [
            F.conditions(linkState: .connecting),
            F.conditions(linkPreference: nil),
            F.conditions(isExternalAdapterUseActive: true),
        ]
        for conditions in blocked {
            AdapterLinkSupervisionResultAssertions.assertIgnored(
                transition.ended(from: .standby, conditions: conditions), from: .standby, "\(conditions)"
            )
        }
    }
}
