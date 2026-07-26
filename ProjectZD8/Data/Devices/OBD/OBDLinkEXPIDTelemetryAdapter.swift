import Foundation

/// OBDLink EXまたはMX+でPID定義DB由来のService 01要求を読み取ります。
actor OBDLinkEXPIDTelemetryAdapter: OBDPIDTelemetryPort {
    /// ELM/STNバイトストリームTransportを生成するFactoryです。
    private let makeTransport: @MainActor @Sendable (OBDConnectionEndpoint) throws -> any OBDCommandTransport
    /// 現在開いているELM/STNバイトストリームTransportです。
    private var activeTransport: (any OBDCommandTransport)?
    /// 現在の単一inflightコマンドチャネルです。
    private var activeChannel: SerializedELMCommandChannel?
    /// 現在の接続資源が属するOBD終端です。
    private var activeEndpoint: OBDConnectionEndpoint?
    /// 現在ELMへ設定している11bit送信ヘッダーです。
    private var activeTransmitHeader: UInt16?

    /// Transport Factoryを固定して生成します。
    ///
    /// 責務: 主要PID読取を物理Transport生成境界へ結び付けます。
    /// - Parameter makeTransport: 接続終端に対応するTransport生成処理。
    init(makeTransport: @escaping @MainActor @Sendable (OBDConnectionEndpoint) throws -> any OBDCommandTransport) {
        self.makeTransport = makeTransport
    }

    /// 指定PIDを同じEXシリアル接続で順番に読み取ります。
    ///
    /// 責務: PID定義DB由来のService 01要求群を1回のEX接続で応答済みバイト辞書へ変換します。
    /// - Parameters:
    ///   - requests: 固定許可リストと照合するService/PID要求。
    ///   - endpoint: EXが公開するUSBシリアル終端。
    /// - Returns: 各要求に対応する未加工データバイト。
    /// - Throws: 非シリアル終端、Service非対応、接続、または初期化に失敗した場合のエラー。
    func read(_ requests: [OBDPIDRequest], using endpoint: OBDConnectionEndpoint) async throws -> [OBDPIDRequest: [UInt8]] {
        guard endpoint.transport.supportsELMByteStream else { throw OBDPIDTelemetryError.unavailable }
        let commands = try requests.map { request -> ELM327CurrentDataCommand in
            guard let command = ELM327CurrentDataCommand(request: request) else {
                throw OBDPIDTelemetryError.unsupportedPID
            }
            return command
        }
        guard !commands.isEmpty else { return [:] }
        do {
            let activeChannel = try await channel(for: endpoint)
            try await setTransmitHeader(0x7DF, using: activeChannel)
            return try await read(commands, using: activeChannel)
        } catch VehicleIdentificationError.responseTimedOut {
            await closeActiveSession()
            throw OBDPIDTelemetryError.noVehicleResponse
        } catch VehicleIdentificationError.connectionFailed {
            await closeActiveSession()
            throw OBDPIDTelemetryError.connectionLost
        } catch {
            await closeActiveSession()
            throw error
        }
    }

    /// 型式確認済み定義を指定ECUへ1件ずつ送信します。
    ///
    /// 責務: 車種専用PID定義群をヘッダー切替済みの応答辞書へ変換します。
    /// - Parameters:
    ///   - definitions: 11bitヘッダーと型式を持つ専用PID定義。
    ///   - endpoint: EXが公開するUSBシリアル終端。
    /// - Returns: 正応答を確認できたService/PIDごとのデータバイト。
    /// - Throws: 定義、ヘッダー、接続、または応答処理に失敗した場合のエラー。
    func readVehicleSpecific(
        _ definitions: [OBDPIDDefinition],
        using endpoint: OBDConnectionEndpoint
    ) async throws -> [OBDPIDRequest: [UInt8]] {
        guard endpoint.transport.supportsELMByteStream else { throw OBDPIDTelemetryError.unavailable }
        let prepared = try definitions.map { definition -> (UInt16, ELM327VehicleSpecificPIDCommand) in
            guard let header = definition.header,
                  let command = ELM327VehicleSpecificPIDCommand(definition: definition) else {
                throw OBDPIDTelemetryError.unsupportedPID
            }
            return (header, command)
        }
        guard !prepared.isEmpty else { return [:] }
        do {
            let channel = try await channel(for: endpoint)
            var result: [OBDPIDRequest: [UInt8]] = [:]
            for (header, command) in prepared {
                try await setTransmitHeader(header, using: channel)
                let response = try await channel.execute(command)
                if let payload = try? ELM327PIDResponseParser().parse(response, request: command.request) {
                    result[command.request] = payload
                }
            }
            return result
        } catch VehicleIdentificationError.responseTimedOut {
            await closeActiveSession()
            throw OBDPIDTelemetryError.noVehicleResponse
        } catch VehicleIdentificationError.connectionFailed {
            await closeActiveSession()
            throw OBDPIDTelemetryError.connectionLost
        } catch {
            await closeActiveSession()
            throw error
        }
    }

    /// 必要な場合だけELM送信ヘッダーを切り替えます。
    ///
    /// 責務: 現在値と異なる1件の11bit CAN IDをELMへ設定します。
    /// - Parameters:
    ///   - header: 設定する11bit CAN ID。
    ///   - channel: 初期化済みELMチャネル。
    /// - Throws: ヘッダー範囲不正またはELM拒否時のエラー。
    private func setTransmitHeader(_ header: UInt16, using channel: SerializedELMCommandChannel) async throws {
        guard activeTransmitHeader != header,
              let command = ELM327TransmitHeaderCommand(header: header) else {
            if activeTransmitHeader == header { return }
            throw OBDPIDTelemetryError.unsupportedPID
        }
        let response = try await channel.execute(command)
        guard isAccepted(response) else { throw OBDPIDTelemetryError.commandRejected }
        activeTransmitHeader = header
    }

    /// ELM設定応答が既知の拒否文字列を含まないか判定します。
    ///
    /// 責務: 1件のELM設定応答を受理可否へ変換します。
    /// - Parameter response: プロンプトを除いたELM設定応答。
    /// - Returns: 空でなく既知の拒否文字列を含まない場合は `true`。
    private func isAccepted(_ response: String) -> Bool {
        let normalized = response.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let rejected = ["?", "ERROR", "UNABLE", "OUT OF MEMORY", "NO DATA", "STOPPED", "BUFFER FULL"]
        return !normalized.isEmpty && !rejected.contains(where: normalized.contains)
    }

    /// 指定終端の再利用可能なコマンドチャネルを返します。
    ///
    /// 責務: 1件のOBD終端を初期化済みの継続シリアルセッションへ変換します。
    /// - Parameter endpoint: PID取得に使用するシリアル終端。
    /// - Returns: 同一終端で再利用する単一inflightコマンドチャネル。
    /// - Throws: Transport生成、接続、またはELM初期化に失敗した場合のエラー。
    private func channel(for endpoint: OBDConnectionEndpoint) async throws -> SerializedELMCommandChannel {
        if activeEndpoint == endpoint, let activeChannel { return activeChannel }
        await closeActiveSession()
        let transport = try await makeTransport(endpoint)
        try await transport.open()
        let channel = SerializedELMCommandChannel(transport: transport)
        do {
            for command in [ELM327Command.reset, .echoOff, .linefeedsOff, .spacesOn, .headersOff, .automaticProtocol] {
                let response = try await channel.execute(command)
                guard isAccepted(response) else { throw OBDPIDTelemetryError.commandRejected }
            }
        } catch {
            await transport.close()
            throw error
        }
        activeTransport = transport
        activeChannel = channel
        activeEndpoint = endpoint
        return channel
    }

    /// 開かれたチャネルでPIDを読み取ります。
    ///
    /// 責務: 1件の初期化済みELMチャネルへPID要求を順番に適用します。
    /// - Parameters:
    ///   - commands: 実行する固定許可済みPIDコマンド。
    ///   - channel: 単一inflightを保つELMチャネル。
    /// - Returns: Service/PIDごとの未加工データバイト。
    /// - Throws: 初期化、読取、または応答解析に失敗した場合のエラー。
    private func read(
        _ commands: [ELM327CurrentDataCommand],
        using channel: SerializedELMCommandChannel
    ) async throws -> [OBDPIDRequest: [UInt8]] {
        var result: [OBDPIDRequest: [UInt8]] = [:]
        for command in commands {
            let response = try await channel.execute(command)
            do {
                result[command.request] = try ELM327PIDResponseParser().parse(
                    response,
                    request: command.request
                )
            } catch OBDPIDTelemetryError.commandRejected {
                continue
            } catch OBDPIDTelemetryError.malformedResponse {
                continue
            }
        }
        return result
    }

    /// 現在の継続取得セッションを終了します。
    ///
    /// 責務: 保持中のシリアルTransportを1回だけ閉じて接続状態を消去します。
    func endSession() async {
        await closeActiveSession()
    }

    /// 保持中のTransportを閉じて再利用状態を解除します。
    ///
    /// 責務: 現在のPID接続資源を閉じた空状態へ遷移させます。
    private func closeActiveSession() async {
        await activeTransport?.close()
        activeTransport = nil
        activeChannel = nil
        activeEndpoint = nil
        activeTransmitHeader = nil
    }
}
