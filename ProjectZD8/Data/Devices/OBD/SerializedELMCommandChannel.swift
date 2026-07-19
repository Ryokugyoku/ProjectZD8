import Foundation

/// 1つのELM/STN接続で同時に1件だけコマンドを実行します。
actor SerializedELMCommandChannel {
    /// コマンドの物理送受信先です。
    private let transport: any OBDCommandTransport
    /// 応答境界を保持できているかどうかです。
    private var isBoundaryEstablished = true

    /// 物理Transportを保持して直列チャネルを生成します。
    ///
    /// 責務: 1件のTransportを単一inflightコマンド境界へ固定します。
    /// - Parameter transport: 開かれたOBDバイトストリーム。
    init(transport: any OBDCommandTransport) {
        self.transport = transport
    }

    /// 型付きコマンドを送ってプロンプト終端応答を返します。
    ///
    /// 責務: 1件の許可済みコマンドを完全応答まで占有して実行します。
    /// - Parameter command: 許可済みELM/STNコマンド。
    /// - Returns: プロンプトを除く加工前応答文字列。
    /// - Throws: 境界喪失、送受信失敗、不正文字列の場合の識別エラー。
    func execute<Command: ELM327CommandEncoding>(_ command: Command) async throws -> String {
        guard isBoundaryEstablished else { throw VehicleIdentificationError.connectionFailed }
        do {
            try await transport.write(command.encodedData)
            let data = try await transport.readUntilPrompt()
            guard let response = String(data: data, encoding: .utf8) else {
                throw VehicleIdentificationError.malformedResponse
            }
            return response.replacingOccurrences(of: ">", with: "")
        } catch {
            isBoundaryEstablished = false
            throw error
        }
    }
}
