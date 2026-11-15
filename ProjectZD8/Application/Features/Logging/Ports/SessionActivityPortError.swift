/// 記録中表示の境界が返す、この製品で定義した失敗です。
nonisolated enum SessionActivityPortError: Error, Equatable, Sendable {
    /// 更新・終了しようとした表示が出ていません。
    case notPresenting
    /// 端末またはユーザー設定で表示が許可されていません。
    case notAuthorized
}
