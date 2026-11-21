#if os(iOS)
/// iOSの車両別一覧で、1件のセッションの手動アップロード欄に出す表示の種類です。
enum IOSConnectionHistoryUploadActionStyle: Equatable {
    /// このセッションを送信中で、進捗を出します。
    case inProgress
    /// 前回の転送に失敗しており、再試行を促します。
    case retry
    /// 通常のアップロード操作を出します。
    case upload

    /// 1件のセッションに出す表示の種類を返します。
    ///
    /// 責務: 送信中のセッションか、iCloud転送の失敗かを、進捗・再試行・通常の順に優先して表示の種類へ変換します。
    /// - Parameters:
    ///   - session: アップロード欄を出すセッション。
    ///   - uploadingSessionID: 送信中のセッションID。どれも送信中でなければ `nil`。
    /// - Returns: アップロード欄の表示の種類。
    static func style(for session: ConnectionSession, uploadingSessionID: ConnectionSessionID?) -> Self {
        if uploadingSessionID == session.id { return .inProgress }
        if session.rawLogSummary.cloudState == .failed { return .retry }
        return .upload
    }
}
#endif
