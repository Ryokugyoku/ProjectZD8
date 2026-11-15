/// 記録セッション終了後の後処理を構成するステップです。実行順は宣言順です。
enum PostSessionProcessingStep: Equatable, Hashable, Sendable, CaseIterable {
    /// 送信待ちセッションのクラウドへのアップロード(端末間同期を含む)です。
    case upload
    /// 保持期限を過ぎたRawキャッシュの端末からの整理です。
    case eviction
}
