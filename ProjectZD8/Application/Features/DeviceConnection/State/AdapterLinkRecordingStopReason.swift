/// 常駐リンク監視が記録の停止を要求する理由です。
///
/// ユーザーの[切断]とリンク断は含みません。ユーザーの[切断]は記録側の操作で、リンク断では停止を要求せず
/// 取得側の猶予に任せるためです。保存する終了理由は既存の `ConnectionSessionEndReason` へ写します。
nonisolated enum AdapterLinkRecordingStopReason: Equatable, Sendable {
    /// サインアウトで稼働条件を失いました。
    case accountSignedOut
    /// 既定アダプターが別のアダプター(別のBLE・Classic・シリアル)へ変わった、または手動接続がアダプターを使い始め、記録が別の接続に置き換わります。
    case superseded
    /// 既定アダプターの削除などで、常駐リンクの接続対象が無くなりました。
    case connectionTargetLost
    /// 監視そのものが停止しました(`AdapterLinkSupervisionUseCase.stop()`)。
    case supervisionStopped

    /// 稼働条件の変化で記録を止める時の理由を返します。
    ///
    /// 責務: サインアウト・監視の停止・既定アダプターの削除・別のアダプターへの変更を、この順に判定して理由を1つに決めます。
    /// 接続対象(既定アダプター)が開始済みリンクの接続対象と異なる時だけ呼ぶ前提です。
    /// - Parameter conditions: 変化後の条件。
    /// - Returns: 未サインインなら `.accountSignedOut`、監視停止なら `.supervisionStopped`、
    ///   既定アダプターが無ければ `.connectionTargetLost`、それ以外(別のBLE・Classic・シリアルへの変更)は `.superseded`。
    static func forOperatingConditionsChange(_ conditions: AdapterLinkSupervisionConditions) -> AdapterLinkRecordingStopReason {
        if !conditions.isSignedIn { return .accountSignedOut }
        if !conditions.isSupervisionStarted { return .supervisionStopped }
        if case .none = conditions.defaultAdapterPreference { return .connectionTargetLost }
        return .superseded
    }

    /// 接続セッションへ保存する終了理由です。
    ///
    /// 責務: 停止理由を既存の終了理由へ写します。新しい終了理由の値は足しません。
    var sessionEndReason: ConnectionSessionEndReason {
        switch self {
        case .accountSignedOut: .accountSignedOut
        case .superseded: .superseded
        case .connectionTargetLost, .supervisionStopped: .connectionLost
        }
    }
}
