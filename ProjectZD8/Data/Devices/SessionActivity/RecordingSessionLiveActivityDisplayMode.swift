/// 記録中のLive Activityをどの表示で描くかです。SwiftUIに依存しない純粋型で、アプリとWidget Extensionの両方に属します。
///
/// 終了表示を最優先し、終了していなくても有効期限を過ぎた(更新が止まった)表示は、状態欄を「更新が止まっています」に替えて
/// 注意のトーンで描きます。計測値は最後に届いた値のまま描きます。
nonisolated enum RecordingSessionLiveActivityDisplayMode: Equatable, Sendable {
    /// 記録中で、更新が届いている表示です。
    case recording
    /// 記録中のまま更新が途絶え、有効期限を過ぎた表示です。
    case stale
    /// 記録が終わった後の終了表示です。
    case ended

    /// 更新が止まった表示の状態欄のローカライズキーです。
    static let staleStatusKey = "live_activity.status.stale"

    /// 表示内容が終了表示かどうかと、システムが古い扱いにしたかどうかから表示を決めます。
    ///
    /// 責務: 終了表示を最優先し、次に古い扱いかどうかで記録中の表示を分けます。
    /// - Parameters:
    ///   - isEnded: 表示内容が終了表示かどうか。
    ///   - isStale: システムが有効期限を過ぎたと判定したかどうか。
    init(isEnded: Bool, isStale: Bool) {
        if isEnded {
            self = .ended
        } else {
            self = isStale ? .stale : .recording
        }
    }

    /// 状態欄に出す文言のローカライズキーを返します。
    ///
    /// 責務: 更新が止まった表示だけ専用の文言へ替え、それ以外は表示内容の文言を使います。
    /// - Parameter state: Live Activityの最新の表示内容。
    /// - Returns: 状態欄のローカライズキー。
    func statusKey(for state: RecordingSessionActivityAttributes.ContentState) -> String {
        self == .stale ? Self.staleStatusKey : state.statusKey
    }

    /// 状態欄の強調を返します。
    ///
    /// 責務: 更新が止まった表示は注意(警告)のトーンにし、それ以外は表示内容の強調を使います。
    /// - Parameter state: Live Activityの最新の表示内容。
    /// - Returns: 状態欄の強調。
    func statusTone(for state: RecordingSessionActivityAttributes.ContentState) -> RecordingSessionActivityAttributes.StatusTone {
        self == .stale ? .warning : state.statusTone
    }
}
