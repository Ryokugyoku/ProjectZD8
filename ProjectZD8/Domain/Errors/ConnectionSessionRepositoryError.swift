/// 接続セッション保存先が提供できない状態です。
enum ConnectionSessionRepositoryError: Error, Equatable {
    /// 製品用の永続化境界を準備できませんでした。
    case unavailable
}
