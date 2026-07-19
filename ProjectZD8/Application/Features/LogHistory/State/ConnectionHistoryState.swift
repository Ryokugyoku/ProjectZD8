/// 接続履歴画面へ公開する読込済み状態です。
struct ConnectionHistoryState: Equatable {
    /// 履歴取得の現在段階です。
    enum Phase: Equatable {
        /// アカウント確定前または読込待ちです。
        case idle
        /// 永続化済み履歴を読み込んでいます。
        case loading
        /// 履歴の読込が完了しました。
        case loaded
        /// 履歴保存先を利用できません。
        case failed
    }

    /// 履歴取得の現在段階です。
    var phase: Phase = .idle
    /// 開始日時が新しい順の接続セッションです。
    var sessions: [ConnectionSession] = []
    /// 直近の読込失敗を示すローカライズキーです。
    var failureKey: String?

    /// 現在接続中のセッション件数です。
    var connectedCount: Int {
        sessions.filter { $0.status == .connected }.count
    }
}
