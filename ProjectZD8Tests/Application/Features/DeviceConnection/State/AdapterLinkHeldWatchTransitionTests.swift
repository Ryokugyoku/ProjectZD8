import XCTest
@testable import ProjectZD8

/// `AdapterLinkHeldWatchTransition` の、ユーザー切断後の抑止中の見張り(開始・継続・解除・上限・前面復帰)を、分岐と境界で検証します。
///
/// 仕様: U3 受け入れ条件 8〜12 と管理チャットの決定 vii(確認の失敗は無応答に数えない)。
/// 見張りの上限は「保持に入ってから8時間を**超えたら**やめる」なので、ちょうど8時間はまだ見張ります。
@MainActor
final class AdapterLinkHeldWatchTransitionTests: XCTestCase {
    /// 共通の fixture です。
    private typealias F = AdapterLinkSupervisionFixtures
    /// 遷移結果の検証手段です。
    private typealias A = AdapterLinkSupervisionResultAssertions

    /// 検証対象の遷移です。
    private let transition = AdapterLinkHeldWatchTransition(timing: .standard)

    /// 見張りを始める前の進行状況です。
    private let awaiting = AdapterLinkHeldWatch.awaitingStart

    /// 見張りを始める前の進行状況は、無応答0回・開始待ちです。
    ///
    /// 責務: `AdapterLinkHeldWatch.awaitingStart` の値を確認します。
    func testAwaitingStartValue() {
        XCTAssertEqual(awaiting, AdapterLinkHeldWatch(consecutiveNoResponses: 0, phase: .awaitingStart))
    }

    /// 記録の終了通知の後、リンクが `ready` で手動接続が使っていなければ、その時刻から8時間の見張りを始め、見張りの確認を送ります。
    ///
    /// 責務: 見張りの終わり=開始時刻+8時間と `.confirmVehicle(.heldWatch)` になることを確認します(仕様 9・11・14)。
    func testRecordingEndSettledStartsWatch() {
        let now = F.date(50)
        let result = transition.recordingEndSettled(awaiting, conditions: F.conditions(now: now))
        A.assertResult(result, state: F.watching(endsAt: now.addingTimeInterval(F.heldWatchSeconds)), effects: [.confirmVehicle(.heldWatch)])
    }

    /// 送れない条件(リンクが `ready` でない・手動接続の使用中)と、既に始めた見張りでは、記録の終了通知で何もしません。
    ///
    /// 責務: 状態がそのままで作用が無いことを確認します(仕様 9・決定 v)。
    func testRecordingEndSettledWithoutSendableConditionsDoesNothing() {
        let cases: [(AdapterLinkHeldWatch, AdapterLinkSupervisionConditions)] = [
            (awaiting, F.conditions(linkState: .connecting)),
            (awaiting, F.conditions(isExternalAdapterUseActive: true)),
            (AdapterLinkHeldWatch(consecutiveNoResponses: 1, phase: .watching(endsAt: F.date(100))), F.conditions()),
        ]
        for (watch, conditions) in cases {
            A.assertIgnored(transition.recordingEndSettled(watch, conditions: conditions), from: .heldAfterUserStop(watch), "\(watch)")
        }
    }

    /// 見張り中の無応答1回目は数を1にして、結果の受信を起点に次の見張りの確認を送ります。
    ///
    /// 責務: 最短間隔以上かかった無応答で、数が1になり `.confirmVehicle(.heldWatch)` が出ることを確認します(仕様 9・10)。
    func testFirstNoResponseCountsAndConfirmsAgain() {
        let conditions = F.conditions(now: F.date(10), lastVehicleConfirmationSentAt: F.date(9))
        let result = transition.confirmationCompleted(.noResponse, watch: watch(0), conditions: conditions)
        A.assertResult(result, state: F.watching(noResponses: 1), effects: [.confirmVehicle(.heldWatch)])
    }

    /// 見張りの確認の結果が最短間隔より早く返ったら、残り時間だけ待ちます(`ATAT0` を受け付けないアダプターでも空回りしない)。
    ///
    /// 責務: 経過0秒の応答で、最短間隔1秒の待ちが予約されることを確認します(仕様 3・9)。
    func testQuickResultWaitsForMinimumInterval() {
        let now = F.date(10)
        let result = transition.confirmationCompleted(.responding, watch: watch(0), conditions: F.conditions(now: now, lastVehicleConfirmationSentAt: now))
        A.assertResult(result, state: F.watching(noResponses: 0), effects: [.scheduleVehicleConfirmation(after: .seconds(1))])
    }

    /// 無応答が連続2回になったら抑止を解き、その時刻から初期化をやり直します。
    ///
    /// 責務: 数1からの無応答で `.initializing(linkReadyAt: now)` と初期化の作用になることを確認します(仕様 10)。
    func testSecondConsecutiveNoResponseReleasesHold() {
        let now = F.date(20)
        let result = transition.confirmationCompleted(.noResponse, watch: watch(1), conditions: F.conditions(now: now))
        A.assertResult(result, state: .initializing(linkReadyAt: now), effects: [.initializeAdapter])
    }

    /// 応答があれば無応答の数を0に戻し、抑止のまま見張りを続けます。
    ///
    /// 責務: 数1からの応答で数が0になることを確認します(仕様 8・10)。
    func testRespondingResetsCount() {
        let conditions = F.conditions(now: F.date(10), lastVehicleConfirmationSentAt: F.date(9))
        let result = transition.confirmationCompleted(.responding, watch: watch(1), conditions: conditions)
        A.assertResult(result, state: F.watching(noResponses: 0), effects: [.confirmVehicle(.heldWatch)])
    }

    /// 見張りの確認の失敗(throw)は無応答に数えず、数を変えずに見張りを続けます。
    ///
    /// 責務: 数1からの失敗で数が1のままで、抑止を解かないことを確認します(決定 vii)。
    func testConfirmationFailureIsNotCountedAsNoResponse() {
        let conditions = F.conditions(now: F.date(10), lastVehicleConfirmationSentAt: F.date(9))
        let result = transition.confirmationFailed(watch(1), conditions: conditions)
        A.assertResult(result, state: F.watching(noResponses: 1), effects: [.confirmVehicle(.heldWatch)])
    }

    /// 保持に入ってから8時間の直前とちょうどでは見張りを続け、直後には見張りをやめて抑止だけを残します。
    ///
    /// 責務: 上限の直前・ちょうどで次の確認が出て、直後では `.stopped` になり作用が無いことを確認します(仕様 11)。
    func testWatchLimitBoundary() {
        let endsAt = F.date(F.heldWatchSeconds)
        for now in [endsAt.addingTimeInterval(-0.001), endsAt] {
            let conditions = F.conditions(now: now, lastVehicleConfirmationSentAt: now.addingTimeInterval(-5))
            let result = transition.confirmationCompleted(.responding, watch: watch(0), conditions: conditions)
            A.assertResult(result, state: F.watching(noResponses: 0), effects: [.confirmVehicle(.heldWatch)], "\(now)")
        }
        let after = endsAt.addingTimeInterval(0.001)
        let stopped = transition.confirmationCompleted(.responding, watch: watch(0), conditions: F.conditions(now: after))
        A.assertResult(stopped, state: .heldAfterUserStop(AdapterLinkHeldWatch(consecutiveNoResponses: 0, phase: .stopped)), effects: [])
    }

    /// 待ち明けでは、見張り中なら見張りの確認を送り、上限を超えていれば見張りをやめ、送れない条件なら何も送りません。
    ///
    /// 責務: `intervalElapsed` の3つの分岐を確認します(仕様 9・11、決定 v)。
    func testIntervalElapsedBranches() {
        let sent = transition.intervalElapsed(watch(1), conditions: F.conditions(now: F.date(10)))
        A.assertResult(sent, state: F.watching(noResponses: 1), effects: [.confirmVehicle(.heldWatch)])

        let expired = transition.intervalElapsed(watch(1), conditions: F.conditions(now: F.date(F.heldWatchSeconds + 1)))
        A.assertResult(expired, state: .heldAfterUserStop(AdapterLinkHeldWatch(consecutiveNoResponses: 1, phase: .stopped)), effects: [])

        let external = transition.intervalElapsed(watch(1), conditions: F.conditions(now: F.date(10), isExternalAdapterUseActive: true))
        A.assertIgnored(external, from: F.watching(noResponses: 1))
    }

    /// 前面復帰では、見張り中なら上限をその時刻から取り直し、やめていた・始めていなかった見張りは確認を送って再開します。
    ///
    /// 責務: 見張り中は終わりの時刻だけが復帰時刻+8時間になり、停止済み・開始待ちは見張りの確認が出ることを確認します(仕様 11)。
    func testAppDidBecomeActiveRenewsOrRestartsWatch() {
        let now = F.date(3_600)
        let renewedEnd = now.addingTimeInterval(F.heldWatchSeconds)
        let extended = transition.appDidBecomeActive(watch(1), conditions: F.conditions(now: now))
        XCTAssertEqual(extended.state, F.watching(noResponses: 1, endsAt: renewedEnd))
        XCTAssertFalse(extended.effects.contains { if case .initializeAdapter = $0 { true } else { false } })

        for previous in [AdapterLinkHeldWatch(consecutiveNoResponses: 0, phase: .stopped), awaiting] {
            let restarted = transition.appDidBecomeActive(previous, conditions: F.conditions(now: now))
            A.assertResult(restarted, state: F.watching(endsAt: renewedEnd), effects: [.confirmVehicle(.heldWatch)], "\(previous)")
        }
    }

    /// 送れない条件(リンクが `ready` でない・手動接続の使用中)の前面復帰では、見張りを再開しません。
    ///
    /// 責務: 状態がそのままで作用が無いことを確認します(仕様 9・決定 v)。
    func testAppDidBecomeActiveWithoutSendableConditionsDoesNothing() {
        for conditions in [F.conditions(linkState: .connecting), F.conditions(isExternalAdapterUseActive: true)] {
            let stopped = AdapterLinkHeldWatch(consecutiveNoResponses: 0, phase: .stopped)
            A.assertIgnored(transition.appDidBecomeActive(stopped, conditions: conditions), from: .heldAfterUserStop(stopped))
        }
    }

    /// 手動接続の使用中は、無応答が連続2回になっても抑止を解かず、見張りの確認も送りません。
    ///
    /// 責務: 数1からの無応答で、初期化にならず作用が無いことを確認します(決定 v)。
    func testNoResponseDuringExternalUseDoesNotRelease() {
        let result = transition.confirmationCompleted(.noResponse, watch: watch(1), conditions: F.conditions(isExternalAdapterUseActive: true))
        XCTAssertTrue(result.state.isHeldAfterUserStop)
        XCTAssertEqual(result.effects, [])
    }

    /// 見張りの開始待ちで手動接続が終わり、リンクが `ready` なら、その時刻から8時間の見張りを始めます。
    ///
    /// 責務: `externalAdapterUseEnded` で、見張りの終わり=受けた時刻+8時間と見張りの確認1件になることを確認します(U8 R5)。
    func testExternalAdapterUseEndedStartsWatchFromAwaitingStart() {
        let now = F.date(45)
        let result = transition.externalAdapterUseEnded(awaiting, conditions: F.conditions(now: now))
        A.assertResult(result, state: F.watching(endsAt: now.addingTimeInterval(F.heldWatchSeconds)), effects: [.confirmVehicle(.heldWatch)])
    }

    /// 見張りの開始待ちで手動接続が終わっても、リンクが `ready` でない・まだ手動接続が使っている・リンク未開始なら始めません。
    ///
    /// 責務: 3つの条件で、開始待ちのまま作用なしであることを確認します(U8 R5 の条件)。
    func testExternalAdapterUseEndedWithoutSendableConditionsKeepsAwaitingStart() {
        let variants = [
            F.conditions(linkState: .connecting),
            F.conditions(isExternalAdapterUseActive: true),
            F.conditions(linkPreference: nil),
        ]
        for conditions in variants {
            A.assertIgnored(transition.externalAdapterUseEnded(awaiting, conditions: conditions), from: .heldAfterUserStop(awaiting), "\(conditions)")
        }
    }

    /// リンク待ちの保持で上限以内にリンクが戻ったら、復帰の時刻から8時間の見張りを始めます。
    ///
    /// 責務: `linkReturned` で、見張りの終わり=復帰時刻+8時間と見張りの確認1件になることを確認します(U8 R4)。
    func testLinkReturnedStartsWatchFromReturnTime() {
        let now = F.date(150)
        let result = transition.linkReturned(.awaitingLink(userStoppedAt: F.date(10)), conditions: F.conditions(now: now))
        A.assertResult(result, state: F.watching(endsAt: now.addingTimeInterval(F.heldWatchSeconds)), effects: [.confirmVehicle(.heldWatch)])
    }

    /// 手動接続の使用中にリンクが戻ったら、確認を送らずに見張りの開始待ちにします。
    ///
    /// 責務: `linkReturned` で `.heldAfterUserStop(.awaitingStart)`・作用なしになることを確認します(U8 R4・R5)。
    func testLinkReturnedWhileExternalAdapterUseAwaitsStart() {
        let result = transition.linkReturned(.awaitingLink(userStoppedAt: F.date(10)), conditions: F.conditions(isExternalAdapterUseActive: true))
        A.assertResult(result, state: .heldAfterUserStop(.awaitingStart), effects: [])
    }

    /// リンク待ちでは、前面復帰しても見張りを始めず、何も送りません。
    ///
    /// 責務: `appDidBecomeActive` を `.awaitingLink` で受けると、状態不変・作用なしであることを確認します(U8 R4)。
    func testAppDidBecomeActiveWhileAwaitingLinkDoesNothing() {
        let waiting = AdapterLinkHeldWatch.awaitingLink(userStoppedAt: F.date(10))
        let result = transition.appDidBecomeActive(waiting, conditions: F.conditions(now: F.date(20), isForeground: true))
        A.assertIgnored(result, from: .heldAfterUserStop(waiting))
    }

    /// リンク待ちでは、記録の終了の確定を受けても見張りを始めません(開始待ちだけが始めます)。
    ///
    /// 責務: `recordingEndSettled` を `.awaitingLink` で受けると、状態不変・作用なしであることを確認します(U8 R4)。
    func testRecordingEndSettledWhileAwaitingLinkDoesNothing() {
        let waiting = AdapterLinkHeldWatch.awaitingLink(userStoppedAt: F.date(10))
        A.assertIgnored(transition.recordingEndSettled(waiting, conditions: F.conditions(now: F.date(20))), from: .heldAfterUserStop(waiting))
    }

    /// リンク待ちの進行状況は、無応答0回・切断の時刻を持つリンク待ちの段階です。
    ///
    /// 責務: `AdapterLinkHeldWatch.awaitingLink(userStoppedAt:)` の値を確認します。
    func testAwaitingLinkValue() {
        let stoppedAt = F.date(10)
        XCTAssertEqual(
            AdapterLinkHeldWatch.awaitingLink(userStoppedAt: stoppedAt),
            AdapterLinkHeldWatch(consecutiveNoResponses: 0, phase: .awaitingLink(userStoppedAt: stoppedAt))
        )
    }

    /// 見張り中の進行状況を作ります。
    ///
    /// 責務: 指定の無応答の数で、基準時刻から8時間後に終わる見張りを返します。
    /// - Parameter noResponses: 連続した無応答の数。
    /// - Returns: 見張りの進行状況。
    private func watch(_ noResponses: Int) -> AdapterLinkHeldWatch {
        AdapterLinkHeldWatch(consecutiveNoResponses: noResponses, phase: .watching(endsAt: F.date(F.heldWatchSeconds)))
    }
}
