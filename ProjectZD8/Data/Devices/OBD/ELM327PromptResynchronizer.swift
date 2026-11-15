import Foundation

/// 応答境界を見失ったELM/STN接続で、次のプロンプトまで読み捨てて境界を合わせ直します。
///
/// 空の復帰文字は直前のコマンドを再実行させるため使いません。代わりに読取専用の識別要求 `ATI` を送り、
/// 識別文字列を含む応答のプロンプトまで読みます。期限切れ後に遅れて届いた応答が先に読める場合があるため、
/// 読取は最大2回(遅れて届いた応答1件と `ATI` の応答)に限ります。各読取はトランスポートのタイムアウトで返ります。
nonisolated struct ELM327PromptResynchronizer: Sendable {
    /// 1回の再同期で読むプロンプト区切りの応答の上限です。
    static let maximumReads = 2

    /// 状態を持たない再同期手順を生成します。
    ///
    /// 責務: プロンプト再同期の手順を構築します。
    init() {}

    /// 識別要求を送り、その応答のプロンプトまでを読み捨てます。
    ///
    /// 責務: 開いているトランスポートの応答境界を `ATI` の応答の直後へ合わせます。
    /// - Parameter transport: 開いているELM/STNバイトストリーム。
    /// - Throws: 上限回数内に識別文字列を含む応答が無い場合は `LiveTelemetryLinkRecoveryError.timedOut`、
    ///   送受信の失敗はトランスポートのエラー。
    func resync(_ transport: any OBDCommandTransport) async throws {
        try await transport.write(ELM327Command.adapterIdentity.encodedData)
        for _ in 0..<Self.maximumReads {
            let data = try await transport.readUntilPrompt()
            let text = String(decoding: data, as: UTF8.self).uppercased()
            if text.contains("ELM") || text.contains("STN") { return }
        }
        throw LiveTelemetryLinkRecoveryError.timedOut
    }
}
