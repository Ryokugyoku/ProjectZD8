/// リモートの変更をローカルへ適用した結果です。
nonisolated enum SyncApplyOutcome: Equatable, Sendable {
    /// ローカルへ書き込み、同期済みにした。
    case applied
    /// ローカルの方が新しいため内容は残し、サーバーのシステムフィールドだけを取り込んだ。
    /// ローカルの変更は引き続き送信待ちです。
    case keptLocal
    /// 親の車両がまだ無いため保留した。車両を適用した時に取り込みます。
    case parked
    /// 親の車両がこの端末で削除待ちのため取り込まなかった。
    case ignored
}
