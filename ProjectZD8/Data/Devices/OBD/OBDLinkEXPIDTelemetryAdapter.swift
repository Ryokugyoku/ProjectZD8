/// OBDLink EXの固定許可コマンドで主要PIDを1回読み取ります。
struct OBDLinkEXPIDTelemetryAdapter: OBDPIDTelemetryPort {
    /// シリアルTransportを生成するFactoryです。
    private let makeTransport: @Sendable (OBDConnectionEndpoint) throws -> any OBDCommandTransport

    /// Transport Factoryを固定して生成します。
    ///
    /// 責務: 主要PID読取を物理Transport生成境界へ結び付けます。
    /// - Parameter makeTransport: 接続終端に対応するTransport生成処理。
    init(makeTransport: @escaping @Sendable (OBDConnectionEndpoint) throws -> any OBDCommandTransport) {
        self.makeTransport = makeTransport
    }

    /// 指定PIDを同じEXシリアル接続で順番に読み取ります。
    ///
    /// 責務: 許可済みPID要求群を1回のEX接続で未加工バイト辞書へ変換します。
    /// - Parameters:
    ///   - requests: 固定許可リストと照合するService/PID要求。
    ///   - endpoint: EXが公開するUSBシリアル終端。
    /// - Returns: 各要求に対応する未加工データバイト。
    /// - Throws: 非シリアル終端、非対応PID、接続、または応答解析に失敗した場合のエラー。
    func read(_ requests: [OBDPIDRequest], using endpoint: OBDConnectionEndpoint) async throws -> [OBDPIDRequest: [UInt8]] {
        guard endpoint.transport == .serial else { throw OBDPIDTelemetryError.unavailable }
        let commands = try requests.map { request -> ELM327CurrentDataCommand in
            guard let command = ELM327CurrentDataCommand(request: request) else {
                throw OBDPIDTelemetryError.unsupportedPID
            }
            return command
        }
        let transport = try makeTransport(endpoint)
        do {
            try await transport.open()
            let result = try await read(commands, using: SerializedELMCommandChannel(transport: transport))
            await transport.close()
            return result
        } catch {
            await transport.close()
            throw error
        }
    }

    /// 開かれたチャネルを初期化してPIDを読み取ります。
    ///
    /// 責務: 1件の開かれたELMチャネルへ初期化と許可済みPID要求を適用します。
    /// - Parameters:
    ///   - commands: 実行する固定許可済みPIDコマンド。
    ///   - channel: 単一inflightを保つELMチャネル。
    /// - Returns: Service/PIDごとの未加工データバイト。
    /// - Throws: 初期化、読取、または応答解析に失敗した場合のエラー。
    private func read(
        _ commands: [ELM327CurrentDataCommand],
        using channel: SerializedELMCommandChannel
    ) async throws -> [OBDPIDRequest: [UInt8]] {
        for command in [ELM327Command.reset, .echoOff, .linefeedsOff, .spacesOn, .headersOff, .automaticProtocol] {
            _ = try await channel.execute(command)
        }
        var result: [OBDPIDRequest: [UInt8]] = [:]
        for command in commands {
            let response = try await channel.execute(command)
            result[command.request] = try ELM327PIDResponseParser().parse(
                response,
                request: command.request
            )
        }
        return result
    }
}
