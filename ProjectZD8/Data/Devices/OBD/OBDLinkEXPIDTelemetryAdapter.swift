import Foundation

/// OBDLink EXでPID定義DB由来のService 01要求を読み取ります。
actor OBDLinkEXPIDTelemetryAdapter: OBDPIDTelemetryPort {
    /// シリアルTransportを生成するFactoryです。
    private let makeTransport: @Sendable (OBDConnectionEndpoint) throws -> any OBDCommandTransport
    /// 現在開いているシリアルTransportです。
    private var activeTransport: (any OBDCommandTransport)?
    /// 現在の単一inflightコマンドチャネルです。
    private var activeChannel: SerializedELMCommandChannel?
    /// 現在の接続資源が属するOBD終端です。
    private var activeEndpoint: OBDConnectionEndpoint?
    /// 2件のBRZ Beta周期メッセージがアダプターへ登録済みかどうかです。
    private var isPeriodicMessagingActive = false

    /// Transport Factoryを固定して生成します。
    ///
    /// 責務: 主要PID読取を物理Transport生成境界へ結び付けます。
    /// - Parameter makeTransport: 接続終端に対応するTransport生成処理。
    init(makeTransport: @escaping @Sendable (OBDConnectionEndpoint) throws -> any OBDCommandTransport) {
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
        guard endpoint.transport == .serial else { throw OBDPIDTelemetryError.unavailable }
        let commands = try requests.map { request -> ELM327CurrentDataCommand in
            guard let command = ELM327CurrentDataCommand(request: request) else {
                throw OBDPIDTelemetryError.unsupportedPID
            }
            return command
        }
        do {
            let activeChannel = try await channel(for: endpoint)
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

    /// 回転数と車速をOBDLinkの周期送信で読み取ります。
    ///
    /// 責務: 固定した2件のService 01要求をSTN周期メッセージと受信バッチへ変換します。
    /// - Parameters:
    ///   - requests: 回転数 `01 0C` と車速 `01 0D` の要求。
    ///   - endpoint: EXが公開するUSBシリアル終端。
    /// - Returns: 今回受信できた要求ごとの未加工データバイト。
    /// - Throws: 対象外要求、周期コマンド非対応、接続、または応答解析失敗の場合のエラー。
    func readPeriodic(
        _ requests: [OBDPIDRequest],
        using endpoint: OBDConnectionEndpoint
    ) async throws -> [OBDPIDRequest: [UInt8]] {
        guard endpoint.transport == .serial,
              Set(requests) == Set(BRZBetaPIDPolicy.requests) else {
            throw OBDPIDTelemetryError.periodicMessagingUnavailable
        }
        do {
            let channel = try await channel(for: endpoint)
            if !isPeriodicMessagingActive {
                try await configurePeriodicMessaging(using: channel)
            }
            let response = try await channel.execute(STNBRZBetaPeriodicCommand.monitorPair)
            var values: [OBDPIDRequest: [UInt8]] = [:]
            for request in requests {
                if let bytes = try? ELM327PIDResponseParser().parse(response, request: request) {
                    values[request] = bytes
                }
            }
            return values
        } catch VehicleIdentificationError.responseTimedOut {
            await closeActiveSession()
            throw OBDPIDTelemetryError.noVehicleResponse
        } catch VehicleIdentificationError.connectionFailed {
            await closeActiveSession()
            throw OBDPIDTelemetryError.connectionLost
        } catch {
            if !isPeriodicMessagingActive { await closeActiveSession() }
            throw error
        }
    }

    /// OBDLinkへ2件の周期メッセージを登録します。
    ///
    /// 責務: 初期化済みELMチャネルを回転数と車速の100ミリ秒周期送信状態へ遷移させます。
    /// - Parameter channel: 単一inflightを保つ初期化済みELMチャネル。
    /// - Throws: STN周期コマンドが拒否された場合は `OBDPIDTelemetryError.periodicMessagingUnavailable`。
    private func configurePeriodicMessaging(using channel: SerializedELMCommandChannel) async throws {
        let clearResponse = try await channel.execute(STNBRZBetaPeriodicCommand.clear)
        guard isAccepted(clearResponse) else { throw OBDPIDTelemetryError.periodicMessagingUnavailable }
        for command in [STNBRZBetaPeriodicCommand.addEngineSpeed, .addVehicleSpeed] {
            let response = try await channel.execute(command)
            guard isAccepted(response) else {
                _ = try? await channel.execute(STNBRZBetaPeriodicCommand.clear)
                throw OBDPIDTelemetryError.periodicMessagingUnavailable
            }
        }
        isPeriodicMessagingActive = true
    }

    /// STNコマンド応答が既知の拒否文字列を含まないか判定します。
    ///
    /// 責務: 1件のSTN応答を周期設定の受理可否へ変換します。
    /// - Parameter response: プロンプトを除いたSTN応答。
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
        let transport = try makeTransport(endpoint)
        try await transport.open()
        let channel = SerializedELMCommandChannel(transport: transport)
        do {
            for command in [ELM327Command.reset, .echoOff, .linefeedsOff, .spacesOn, .headersOff, .automaticProtocol] {
                _ = try await channel.execute(command)
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
        if isPeriodicMessagingActive, let activeChannel {
            _ = try? await activeChannel.execute(STNBRZBetaPeriodicCommand.clear)
        }
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
        isPeriodicMessagingActive = false
    }
}
