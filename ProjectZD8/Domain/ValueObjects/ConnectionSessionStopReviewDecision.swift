/// 自動判別できない接続終了をユーザーがどのように確認したかを表します。
enum ConnectionSessionStopReviewDecision: String, Codable, Equatable, Sendable {
    /// ユーザーが意図してイグニッションを切るかデバイスを外した終了です。
    case userInitiated
}
