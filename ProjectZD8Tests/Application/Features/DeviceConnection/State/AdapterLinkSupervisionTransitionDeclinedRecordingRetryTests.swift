import XCTest
@testable import ProjectZD8

/// `AdapterLinkSupervisionTransition` が、監視下の記録開始が辞退・失敗(終了理由なし)で終わった後、
/// リンクが `ready` なら延長確認と同じ間隔(5秒)の待ちを挟んでから車両確認(再初期化)へ戻ることを検証します(S1-3)。
///
/// 記録終了の通知から待機へ落ち着くまでは、ユースケースと同じく `.completeFinishing` の作用に `finishingDidComplete` を返して進めます。
/// 待ちの作用は、待ち明けで再初期化を促す `.scheduleAdapterInitializationRetry(after:)` です。
@MainActor
final class AdapterLinkSupervisionTransitionDeclinedRecordingRetryTests: XCTestCase {
    /// 共通の fixture です。
    private typealias F = AdapterLinkSupervisionFixtures

    /// 遷移結果の検証手段です。
    private typealias A = AdapterLinkSupervisionResultAssertions

    /// 記録終了の通知から落ち着くまでに処理するイベント数の上限です。連鎖が止まらない不具合を失敗にします。
    private let maximumChainedEvents = 8

    /// 記録中の状態です。
    private let recording = AdapterLinkSupervisionState.recording(F.detectedVehicle)

    /// 記録終了の通知を入力し、`.completeFinishing` の作用には `finishingDidComplete` を返して、落ち着くまで進めます。
    ///
    /// 責務: ユースケースと同じ順で連鎖を処理し、最後の状態と出た作用の全てを返します。上限を超えたら失敗させます。
    /// - Parameters:
    ///   - transition: 検証対象の遷移。
    ///   - endReason: 記録終了の理由。
    ///   - conditions: 全イベントで使う条件。
    /// - Returns: 落ち着いた状態と、連鎖で出た全ての作用(出た順)。
    private func settleFinish(
        _ transition: AdapterLinkSupervisionTransition,
        endReason: ConnectionSessionEndReason?,
        conditions: AdapterLinkSupervisionConditions,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> (state: AdapterLinkSupervisionState, effects: [AdapterLinkSupervisionEffect]) {
        var state = recording
        var effects: [AdapterLinkSupervisionEffect] = []
        var pending: [AdapterLinkSupervisionEvent] = [.recordingDidFinish(endReason: endReason)]
        var processed = 0
        while !pending.isEmpty, processed < maximumChainedEvents {
            let result = transition.result(from: state, on: pending.removeFirst(), conditions: conditions)
            state = result.state
            effects += result.effects
            pending += result.effects.filter { $0 == .completeFinishing }.map { _ in .finishingDidComplete }
            processed += 1
        }
        XCTAssertTrue(pending.isEmpty, "連鎖が\(maximumChainedEvents)件で止まらない: \(effects)", file: file, line: line)
        return (state, effects)
    }

    /// 作用の列に含まれる、再初期化を促す待ちの作用だけを返します。
    ///
    /// 責務: `.scheduleAdapterInitializationRetry(after:)` の待ち時間を出た順に取り出します。
    /// - Parameter effects: 連鎖で出た作用。
    /// - Returns: 待ち時間の列。
    private func retryWaits(in effects: [AdapterLinkSupervisionEffect]) -> [Duration] {
        effects.compactMap { if case let .scheduleAdapterInitializationRetry(duration) = $0 { duration } else { nil } }
    }

    /// 作用の列に、待ちを挟まずにアダプターへ送る作用(初期化・車両確認)が含まれるかを返します。
    ///
    /// 責務: 即時の再開(`.initializeAdapter`・`.confirmVehicle`・`.readVIN`)の有無を判定します。
    /// - Parameter effects: 連鎖で出た作用。
    /// - Returns: 1件でも含めば `true`。
    private func containsImmediateAdapterWork(_ effects: [AdapterLinkSupervisionEffect]) -> Bool {
        effects.contains {
            switch $0 {
            case .initializeAdapter, .confirmVehicle, .readVIN: true
            default: false
            }
        }
    }

    /// リンクが `ready` で記録開始が辞退・失敗で終わったら、待機へ落ち着き、5秒の待ちを1件だけ予約します。即座には再初期化しません。
    ///
    /// 責務: 前面・背面の両方で、最後の状態が待機・待ちの予約が `[5秒]`・初期化/確認の即時送信なし・通知の取り下げありを確認します(S1-3)。
    func testDeclinedFinishWithReadyLinkSchedulesFiveSecondWaitBeforeReinitializing() {
        for isForeground in [false, true] {
            let settled = settleFinish(AdapterLinkSupervisionTransition(), endReason: nil, conditions: F.conditions(isForeground: isForeground))
            XCTAssertEqual(settled.state, .standby, "前面 \(isForeground)")
            XCTAssertEqual(retryWaits(in: settled.effects), [.seconds(5)], "前面 \(isForeground) \(settled.effects)")
            XCTAssertFalse(containsImmediateAdapterWork(settled.effects), "待ちを挟まずに再開した: \(settled.effects)")
            XCTAssertTrue(settled.effects.contains(.dismissNotification), "\(settled.effects)")
            XCTAssertFalse(A.containsRecordingStopRequest(settled.effects), "\(settled.effects)")
        }
    }

    /// 辞退後の待ちは、延長確認と同じ間隔(`extendedConfirmationInterval`)です。
    ///
    /// 責務: 延長確認7秒・初期化の再試行11秒の時間定数で、辞退後の待ちが7秒になることを確認します(S1-3「延長確認と同じ間隔」)。
    func testDeclinedFinishWaitUsesExtendedConfirmationInterval() {
        let timing = AdapterLinkSupervisionTiming(
            vehicleConfirmationWindow: 600, vehicleConfirmationInterval: 1,
            extendedConfirmationInterval: 7, initializationRetryInterval: 11
        )
        let settled = settleFinish(AdapterLinkSupervisionTransition(timing: timing), endReason: nil, conditions: F.conditions())
        XCTAssertEqual(settled.state, .standby)
        XCTAssertEqual(retryWaits(in: settled.effects), [.seconds(7)], "\(settled.effects)")
    }

    /// 辞退後の待ちが明けたら、待機でリンクが `ready` なら、その時刻を窓の起点として再初期化します。
    ///
    /// 責務: 落ち着いた状態へ待ち明け(`adapterInitializationRetryElapsed`)を5秒後の時刻で入力し、
    /// `initializing(linkReadyAt: 5秒後)` と初期化の作用になることを確認します(S1-3)。
    func testRetryElapsedAfterDeclinedFinishReinitializes() {
        let transition = AdapterLinkSupervisionTransition()
        let settled = settleFinish(transition, endReason: nil, conditions: F.conditions())
        let now = F.date(5)
        let result = transition.result(from: settled.state, on: .adapterInitializationRetryElapsed, conditions: F.conditions(now: now))
        A.assertResult(result, state: .initializing(linkReadyAt: now), effects: [.initializeAdapter])
    }

    /// リンクが `ready` でない・リンク未開始なら、辞退・失敗で終わっても待ちを予約せず待機のままです(従来どおり)。
    ///
    /// 責務: 各条件で、最後の状態が待機・待ちの予約なし・初期化/確認の即時送信なしを確認します(S1-3)。
    func testDeclinedFinishWithoutReadyLinkStaysInStandbyWithoutWait() {
        let blocked = [F.conditions(linkState: .connecting), F.conditions(linkPreference: nil)]
        for conditions in blocked {
            let settled = settleFinish(AdapterLinkSupervisionTransition(), endReason: nil, conditions: conditions)
            XCTAssertEqual(settled.state, .standby, "\(conditions)")
            XCTAssertEqual(retryWaits(in: settled.effects), [], "\(conditions) \(settled.effects)")
            XCTAssertFalse(containsImmediateAdapterWork(settled.effects), "\(conditions) \(settled.effects)")
        }
    }

    /// 終了理由のある終了(ユーザー切断以外)では待ちを予約せず、従来どおり `recordingEndSettled` ですぐ再確認します。
    ///
    /// 責務: 接続断・車両無応答・取得失敗の終了で待機へ落ち着き待ちの予約がないこと、続く `recordingEndSettled` で
    /// `initializing(linkReadyAt: now)` と初期化の作用になることを確認します(S1-4)。
    func testFinishWithEndReasonRestartsViaRecordingEndSettledWithoutWait() {
        let transition = AdapterLinkSupervisionTransition()
        for reason in [ConnectionSessionEndReason.connectionLost, .vehicleNoResponse, .acquisitionFailed] {
            let settled = settleFinish(transition, endReason: reason, conditions: F.conditions())
            XCTAssertEqual(settled.state, .standby, "\(reason)")
            XCTAssertEqual(retryWaits(in: settled.effects), [], "\(reason) \(settled.effects)")

            let now = F.date(1)
            let restarted = transition.result(from: settled.state, on: .recordingEndSettled, conditions: F.conditions(now: now))
            A.assertResult(restarted, state: .initializing(linkReadyAt: now), effects: [.initializeAdapter], "\(reason)")
        }
    }
}
