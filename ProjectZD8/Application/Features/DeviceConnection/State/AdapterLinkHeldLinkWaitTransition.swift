import Foundation

/// リンク待ちの保持(リンクが `ready` でない間のユーザー切断の後)で、リンク状態の変化を扱う純粋な遷移です。
///
/// ユーザー切断の時刻から上限(既定3分。ちょうどを含む。単調時計基準)以内にリンクが `ready` へ戻れば、同じ走行とみなして
/// 保持を続け、復帰の時刻から見張りを始めます(`AdapterLinkHeldWatchTransition.linkReturned`)。上限を超えてから戻れば、
/// 保持は解けたものとして、待機からの再接続と同じく初期化から検知を始めます。上限の経過はタイマーで測らず、
/// リンク状態の変化が届いた時に判定します。リンク待ちの間はアダプターへ何も送りません。
nonisolated struct AdapterLinkHeldLinkWaitTransition: Sendable {
    /// 同じ走行とみなす上限の定数です。
    let timing: AdapterLinkSupervisionTiming

    /// 見張りを始める遷移です。
    private let heldWatch: AdapterLinkHeldWatchTransition

    /// 時間定数を固定して生成します。
    ///
    /// 責務: リンク待ちの上限と見張りの遷移を結び付けます。
    /// - Parameter timing: リンク待ちの上限と見張りの上限。
    init(timing: AdapterLinkSupervisionTiming) {
        self.timing = timing
        heldWatch = AdapterLinkHeldWatchTransition(timing: timing)
    }

    /// リンク待ちの保持でリンク状態が変わった時の遷移を返します。
    ///
    /// 責務: `ready` への変化を、上限以内なら見張りの開始へ、超えていれば初期化からの検知へ変換します。
    /// `ready` 以外への変化は、上限以内なら保持のまま、超えていれば待機へ戻します(どちらも作用なし)。
    /// - Parameters:
    ///   - linkState: 変化後のリンク状態。
    ///   - userStoppedAt: ユーザーが切断した時刻。
    ///   - watch: 現在の見張りの進行状況。
    ///   - conditions: 現在時刻と手動接続の使用中かどうかを含む条件。
    /// - Returns: 次の状態と作用。開始していないリンクの変化は無視します。
    func linkStateChanged(
        to linkState: AdapterLinkState,
        userStoppedAt: Date,
        watch: AdapterLinkHeldWatch,
        conditions: AdapterLinkSupervisionConditions
    ) -> AdapterLinkSupervisionTransitionResult {
        let state = AdapterLinkSupervisionState.heldAfterUserStop(watch)
        guard conditions.linkPreference != nil else {
            return AdapterLinkSupervisionTransitionResult(state: state)
        }
        let isSameDrive = isWithinLimit(userStoppedAt: userStoppedAt, now: conditions.now)
        if linkState == .ready {
            return isSameDrive ? heldWatch.linkReturned(watch, conditions: conditions) : newDriveStarted(conditions: conditions)
        }
        return AdapterLinkSupervisionTransitionResult(state: isSameDrive ? state : .standby)
    }

    /// 時刻が、ユーザー切断から同じ走行とみなす上限以内かどうかを返します。
    ///
    /// 責務: 切断の時刻に上限を足した時刻以前(ちょうどを含む)であることを判定します。
    /// - Parameters:
    ///   - userStoppedAt: ユーザーが切断した時刻。
    ///   - now: 判定する時刻。
    /// - Returns: 上限以内なら `true`。
    func isWithinLimit(userStoppedAt: Date, now: Date) -> Bool {
        now <= userStoppedAt.addingTimeInterval(timing.heldLinkWaitLimit)
    }

    /// 上限を超えてリンクが戻った時に、新しい走行として検知を始める遷移を返します。
    ///
    /// 責務: 手動接続が使っていなければ、復帰の時刻を窓の起点として初期化を始めます。使っている間は待機へ戻します
    /// (待機での再接続と同じく、使い終えた後の再接続か前面復帰で初期化します)。
    /// - Parameter conditions: 復帰の時刻と手動接続の使用中かどうかを含む条件。
    /// - Returns: 初期化中または待機への遷移。
    private func newDriveStarted(conditions: AdapterLinkSupervisionConditions) -> AdapterLinkSupervisionTransitionResult {
        guard !conditions.isExternalAdapterUseActive else {
            return AdapterLinkSupervisionTransitionResult(state: .standby)
        }
        return AdapterLinkSupervisionTransitionResult(state: .initializing(linkReadyAt: conditions.now), effects: [.initializeAdapter])
    }
}
