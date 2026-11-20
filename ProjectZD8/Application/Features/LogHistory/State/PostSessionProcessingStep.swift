/// 記録セッション終了後の後処理を構成するステップです。実行順は宣言順(Rawのアップロード → 走行ルートのアップロード → 整理)です。
///
/// 順序の理由: 整理はRawを端末から消すため、CloudKitへの保存が確認できたセッションだけを対象にします
/// (`ConnectionSessionRawCacheRetentionPolicy.shouldEvict` が、終了済み・端末にRawあり・`cloudState == .uploaded`・
/// manifest digest あり・最後の閲覧(無ければ終了時刻)から保持期間3日以上、をすべて満たす時だけ許可)。
/// 先にアップロードすることで、送信待ちのまま保持期間を過ぎたセッションも、同じ実行の中で保存を確かめてから整理できます。
/// 逆順にすると、未保存のRawは整理されないものの、アップロード済みにした分の整理が次回まで持ち越されます。
enum PostSessionProcessingStep: Equatable, Hashable, Sendable, CaseIterable {
    /// 送信待ちセッションのクラウドへのアップロード(端末間同期を含む)です。
    case upload
    /// 走行ルート(位置の軌跡)のクラウドへのアップロードです。Rawと同じく自動アップロードがオンの時だけ実行します。
    case locationTrackUpload
    /// 保持期限を過ぎたRawキャッシュの端末からの整理です。
    case eviction

    /// 自動アップロードの設定がオンの時だけ実行するステップかどうかです。
    ///
    /// `upload` と `locationTrackUpload` が `true` で、端末内の整理である `eviction` は `false` です。
    var requiresAutomaticUpload: Bool {
        switch self {
        case .upload, .locationTrackUpload: true
        case .eviction: false
        }
    }
}
