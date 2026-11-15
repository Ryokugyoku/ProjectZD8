/// 記録中の常時表示(Live Activity)の状態遷移の診断記録を、統合ログへ出す固定文言へ整形します。
///
/// 実機テスト手順書がこの文字列を参照するため、文言を変える場合は手順書も合わせて直します。
struct RecordingSessionActivityLifecycleDiagnosticsMessageFormatter {
    /// 文言の共通の接頭辞です。
    private static let prefix = "Live Activity"

    /// 表示を開始できたときの文言です。
    ///
    /// 責務: 表示開始を固定文言へ変換します。
    /// - Returns: `Live Activity started`。
    func started() -> String {
        "\(Self.prefix) started"
    }

    /// アプリが表示を終了したときの文言です。
    ///
    /// 責務: アプリによる表示終了を固定文言へ変換します。
    /// - Returns: `Live Activity ended`。
    func ended() -> String {
        "\(Self.prefix) ended"
    }

    /// システムまたはユーザーに表示を閉じられたときの文言です。
    ///
    /// 責務: アプリ以外による表示終了を固定文言へ変換します。
    /// - Returns: `Live Activity closed by system`。
    func closedBySystem() -> String {
        "\(Self.prefix) closed by system"
    }

    /// [切断]の要求を受け付けたときの文言です。
    ///
    /// 責務: 受け付けた停止要求を固定文言へ変換します。
    /// - Returns: `Live Activity stop requested: accepted`。
    func stopRequestAccepted() -> String {
        "\(Self.prefix) stop requested: accepted"
    }

    /// [切断]の要求を断ったときの文言です。
    ///
    /// 責務: 断った停止要求を固定文言へ変換します。
    /// - Returns: `Live Activity stop requested: declined`。
    func stopRequestDeclined() -> String {
        "\(Self.prefix) stop requested: declined"
    }
}
