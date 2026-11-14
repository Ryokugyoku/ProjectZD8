import Foundation

/// プロセス復帰時に未終了だったセッションの処理結果です。
nonisolated enum ConnectionSessionRelaunchOutcome: Equatable, Sendable {
    /// 猶予内のため、次の取得で同じセッションの新しい区間として続けられます。
    /// - Parameters:
    ///   - session: 未終了のままのセッション。
    ///   - lastCommittedAt: 最後にcommitしたRawの観測時刻(Rawが無ければセッション開始時刻)。
    case resumable(ConnectionSession, lastCommittedAt: Date)
    /// 猶予を超えたため、最後にcommitした時刻で終了しました。
    case ended(ConnectionSession)
}
