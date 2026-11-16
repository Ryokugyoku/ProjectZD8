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
            case .stopLink, .startLink, .initializeAdapter, .confirmVehicle, .scheduleVehicleConfirmation, .readVIN,
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

    /// 手動使用が終わっても、どの状態でもすぐには何もしません(再確認は次の再接続か前面復帰まで待つ)。
    ///
    /// 責務: 全状態で状態不変・作用なしであることを確認します。
    func testEndedIsIgnoredInEveryState() {
        for state in F.allStates {
            AdapterLinkSupervisionResultAssertions.assertIgnored(transition.ended(from: state), from: state, "\(state)")
        }
    }
}
