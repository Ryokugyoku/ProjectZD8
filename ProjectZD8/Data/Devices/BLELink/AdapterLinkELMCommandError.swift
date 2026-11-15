/// 常駐リンク上の監視用ELM/STNコマンドが、通信は届いたのに期待した応答を返さなかった理由です。
nonisolated enum AdapterLinkELMCommandError: Error, Equatable, Sendable {
    /// アダプターがコマンドを `?` で拒否しました。対象コマンドの要求識別子を保持します。
    case commandRejected(requestID: String)

    /// 応答をUTF-8の文字列として解釈できませんでした。対象コマンドの要求識別子を保持します。
    case malformedResponse(requestID: String)
}
