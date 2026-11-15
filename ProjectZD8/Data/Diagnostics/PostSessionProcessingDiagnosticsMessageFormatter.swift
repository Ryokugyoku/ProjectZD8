/// 記録セッション終了後の後処理の診断記録を、統合ログへ出す固定文言へ整形します。
///
/// 実機テスト手順書がこの文字列を参照するため、文言を変える場合は手順書も合わせて直します。
struct PostSessionProcessingDiagnosticsMessageFormatter {
    /// 文言の共通の接頭辞です。
    private static let prefix = "Post-session processing"

    /// 予約に成功したときの文言です。
    ///
    /// 責務: 予約成功を固定文言へ変換します。
    /// - Returns: `Post-session processing scheduled`。
    func scheduled() -> String {
        "\(Self.prefix) scheduled"
    }

    /// 予約に失敗したときの文言です。
    ///
    /// 責務: 予約失敗のエラー分類を固定文言へ変換します。
    /// - Parameters:
    ///   - errorDomain: 失敗したエラーの `domain`。
    ///   - errorCode: 失敗したエラーの `code`。
    /// - Returns: `Post-session processing schedule failed: <domain> <code>`。
    func scheduleFailed(errorDomain: String, errorCode: Int) -> String {
        "\(Self.prefix) schedule failed: \(errorDomain) \(errorCode)"
    }

    /// 実行を始めたときの文言です。
    ///
    /// 責務: 実行開始を固定文言へ変換します。
    /// - Returns: `Post-session processing started`。
    func started() -> String {
        "\(Self.prefix) started"
    }

    /// 記録中のため持ち越したときの文言です。
    ///
    /// 責務: 記録中による持ち越しを固定文言へ変換します。
    /// - Returns: `Post-session processing deferred: recording active`。
    func deferredForActiveRecording() -> String {
        "\(Self.prefix) deferred: recording active"
    }

    /// アカウント未解決のため持ち越したときの文言です。
    ///
    /// 責務: アカウント未解決による持ち越しを固定文言へ変換します。
    /// - Returns: `Post-session processing deferred: account unavailable`。
    func deferredForUnavailableAccount() -> String {
        "\(Self.prefix) deferred: account unavailable"
    }

    /// 自動アップロードがオフのためアップロードを省いたときの文言です。
    ///
    /// 責務: 設定によるアップロード省略を固定文言へ変換します。
    /// - Returns: `Post-session processing step upload skipped: automatic upload off`。
    func uploadSkippedForAutomaticUploadOff() -> String {
        "\(Self.prefix) step \(Self.name(of: .upload)) skipped: automatic upload off"
    }

    /// ステップが成功したときの文言です。
    ///
    /// 責務: ステップ成功を固定文言へ変換します。
    /// - Parameter step: 成功したステップ。
    /// - Returns: `Post-session processing step <upload|eviction> succeeded`。
    func stepSucceeded(_ step: PostSessionProcessingStep) -> String {
        "\(Self.prefix) step \(Self.name(of: step)) succeeded"
    }

    /// ステップが失敗したときの文言です。
    ///
    /// 責務: ステップ失敗とエラー分類を固定文言へ変換します。
    /// - Parameters:
    ///   - step: 失敗したステップ。
    ///   - errorDomain: 失敗したエラーの `domain`。
    ///   - errorCode: 失敗したエラーの `code`。
    /// - Returns: `Post-session processing step <upload|eviction> failed: <domain> <code>`。
    func stepFailed(_ step: PostSessionProcessingStep, errorDomain: String, errorCode: Int) -> String {
        "\(Self.prefix) step \(Self.name(of: step)) failed: \(errorDomain) \(errorCode)"
    }

    /// 期限切れで中断したときの文言です。
    ///
    /// 責務: 期限切れによる中断を固定文言へ変換します。
    /// - Returns: `Post-session processing interrupted: expired`。
    func interruptedByExpiration() -> String {
        "\(Self.prefix) interrupted: expired"
    }

    /// 実行を終えたときの文言です。
    ///
    /// 責務: 実行結果を completed か incomplete の固定文言へ変換します。
    /// - Parameter outcome: 実行結果。
    /// - Returns: `Post-session processing finished: completed` または `Post-session processing finished: incomplete`。
    func finished(_ outcome: PostSessionProcessingOutcome) -> String {
        "\(Self.prefix) finished: \(outcome == .completed ? "completed" : "incomplete")"
    }

    /// ステップの文言上の名前です。
    ///
    /// 責務: ステップを `upload` または `eviction` へ変換します。
    /// - Parameter step: 名前にするステップ。
    /// - Returns: ステップの名前。
    private static func name(of step: PostSessionProcessingStep) -> String {
        switch step {
        case .upload: "upload"
        case .eviction: "eviction"
        }
    }
}
