import Foundation

/// ユーザー切断後の抑止中に、同じ走行が続いているかを見張る確認の段階です。
nonisolated enum AdapterLinkHeldWatchPhase: Equatable, Sendable {
    /// リンクが `ready` でない間にユーザーが切断し、リンクの復帰を待っています(リンク待ちの保持)。アダプターへは何も送りません。
    ///
    /// `userStoppedAt` から上限(`AdapterLinkSupervisionTiming.heldLinkWaitLimit`。ちょうどを含む)以内にリンクが `ready` へ戻れば
    /// 同じ走行として見張りを始め、超えてから戻れば新しい走行として通常の検知を行います(単調時計基準の時刻)。
    case awaitingLink(userStoppedAt: Date)
    /// 抑止に入った直後で、記録の終了通知を受けた後の見張りの開始を待っています(記録の終了処理中はアダプターへ何も送りません)。
    case awaitingStart
    /// 見張りの確認を続けています。`endsAt` を過ぎたら見張りをやめます(安全上限。単調時計基準の時刻)。
    case watching(endsAt: Date)
    /// 安全上限を過ぎて見張りをやめました。従来の抑止(リンク断・稼働条件の変化・前面復帰で動く)に戻っています。
    case stopped
}
