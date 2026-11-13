/// 接続セッション保存先が提供できない状態です。
enum ConnectionSessionRepositoryError: Error, Equatable {
    /// 製品用の永続化境界を準備できませんでした。
    case unavailable
    /// 指定操作を現在のセッション状態では実行できません。
    case invalidState
    /// 同じ安定IDに異なるセッションまたはManifestが存在します。
    case integrityConflict
}
