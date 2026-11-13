/// ログ履歴で起きる失敗を、画面が文言へ変換できる型で表します。
nonisolated enum LogHistoryFailure: Error, Equatable, Sendable {
    /// セッション一覧を読み込めなかった。
    case loadFailed
    /// 対象のセッションが見つからなかった。
    case sessionNotFound
    /// 記録中のセッションは削除できない。
    case deleteRefusedWhileRecording
    /// セッションを削除できなかった。
    case deleteFailed
    /// iCloudへ保存済みでない、または既に解放済みのため、この端末の領域を解放できない。
    case freeUpSpaceNotAllowed
    /// この端末の領域を解放できなかった。
    case freeUpSpaceFailed

    /// 画面表示に使用するローカライズキーです。
    var localizationKey: String {
        switch self {
        case .loadFailed: "history.error.load"
        case .sessionNotFound: "history.error.not_found"
        case .deleteRefusedWhileRecording: "history.error.delete_recording"
        case .deleteFailed: "history.error.delete"
        case .freeUpSpaceNotAllowed: "history.error.free_up_not_allowed"
        case .freeUpSpaceFailed: "history.error.free_up"
        }
    }
}
