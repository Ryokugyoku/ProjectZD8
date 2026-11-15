/// 台本付きリンク fake へ渡す ELM/STN の応答テキストの例です。
///
/// 応答は実機の ELM327 の形(応答行の後に空行とプロンプト `>`)に合わせています。
enum AdapterLinkELMReplyFixtures {
    /// 設定コマンドを受け付けた応答です。
    static let ok = "OK\r\r>"
    /// コマンドを理解しなかった応答です。
    static let rejected = "?\r\r>"
    /// STN チップの `STI` 応答です。
    static let stnIdentity = "STN2120 v5.6.19\r\r>"
    /// ELM327 v1.5 を名乗る `ATI` 応答です。
    static let elmVersion15 = "ELM327 v1.5\r\r>"
    /// ELM327 v2.1 を名乗る `ATI` 応答です。
    static let elmVersion21 = "ELM327 v2.1\r\r>"
    /// `0100` への ECU の正応答です。
    static let supportedPIDsPositive = "41 00 BE 3E B8 13 \r\r>"
    /// ヘッダー表示ありで受信監視が拾う CAN フレームの列です(プロンプトなし)。
    static let monitorFrames = "7E8 03 41 0D 00\r7E8 04 41 0C 1A F8\r"

    /// 通常に初期化できるアダプターの応答一式を作ります。
    ///
    /// 責務: 設定・タイムアウト設定コマンドを受け付け、識別応答だけを指定値にした台本を返します。
    /// - Parameters:
    ///   - stnIdentity: `STI` への応答。
    ///   - adapterIdentity: `ATI` への応答。
    /// - Returns: コマンドごとの応答。
    static func initializableAdapter(stnIdentity: String, adapterIdentity: String) -> [String: String] {
        var replies: [String: String] = [
            "ATZ": "\r\rELM327 v1.5\r\r>",
            "STI": stnIdentity,
            "ATI": adapterIdentity,
            "ATST32": ok,
            "ATSTFF": ok,
            "0100": supportedPIDsPositive
        ]
        for command in ["ATE0", "ATL0", "ATS1", "ATH0", "ATH1", "ATSP0"] {
            replies[command] = ok
        }
        return replies
    }
}
