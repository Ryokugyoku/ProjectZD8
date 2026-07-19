import Foundation

/// OBDLink EXへ安全な型付きコマンドだけを送りVINを取得します。
struct OBDLinkEXVehicleIdentificationAdapter: VehicleIdentificationPort {
    /// シリアルTransportを生成するFactoryです。
    private let makeTransport: @Sendable (OBDConnectionEndpoint) throws -> any OBDCommandTransport
    /// 観測日時を提供する注入済みクロックです。
    private let now: @Sendable () -> Date

    /// Transport Factoryとクロックを注入して生成します。
    ///
    /// 責務: EX車両識別処理を物理Transport生成と時刻取得境界へ固定します。
    /// - Parameters:
    ///   - makeTransport: 接続終端に対応するTransport生成処理。
    ///   - now: 観測完了日時の供給元。
    init(
        makeTransport: @escaping @Sendable (OBDConnectionEndpoint) throws -> any OBDCommandTransport,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.makeTransport = makeTransport
        self.now = now
    }

    /// OBDLink EXを初期化してService 09 PID 02のVINを取得します。
    ///
    /// 責務: 1件のEXシリアル接続から型付き読取専用識別観測を生成します。
    /// - Parameter endpoint: EXが公開するUSBシリアル終端。
    /// - Returns: VIN、アダプター、プロトコル、加工前応答を含む観測。
    /// - Throws: 非シリアル終端、接続、コマンド、応答解析に失敗した場合の識別エラー。
    func identifyVehicle(using endpoint: OBDConnectionEndpoint) async throws -> VehicleIdentificationSnapshot {
        guard endpoint.transport == .serial else { throw VehicleIdentificationError.transportUnsupported }
        let transport = try makeTransport(endpoint)
        do {
            try await transport.open()
            let snapshot = try await identify(using: SerializedELMCommandChannel(transport: transport), endpoint: endpoint)
            await transport.close()
            return snapshot
        } catch {
            await transport.close()
            throw error
        }
    }

    /// 開かれた直列チャネルで初期化とVIN要求を実行します。
    ///
    /// 責務: 1件の開かれたEXチャネルへ承認済み識別コマンド列を適用します。
    /// - Parameters:
    ///   - channel: 単一inflightを保証するELMコマンドチャネル。
    ///   - endpoint: 表示用アダプター情報を持つ接続終端。
    /// - Returns: VINと全原文応答を保持する観測。
    /// - Throws: いずれかのコマンドまたはVIN解析に失敗した場合のエラー。
    private func identify(using channel: SerializedELMCommandChannel, endpoint: OBDConnectionEndpoint) async throws -> VehicleIdentificationSnapshot {
        var raw: [VehicleIdentificationSnapshot.RawResponse] = []
        for command in [.reset, .echoOff, .linefeedsOff, .spacesOn, .headersOff, .automaticProtocol] as [ELM327Command] {
            let response = try await channel.execute(command)
            try validate(response)
            raw.append(.init(requestID: command.requestID, payload: response))
        }
        let adapterResponse = try await channel.execute(ELM327Command.adapterIdentity)
        try validate(adapterResponse)
        raw.append(.init(requestID: ELM327Command.adapterIdentity.requestID, payload: adapterResponse))

        let deviceInformation = try await channel.execute(ELM327Command.extendedDeviceInformation)
        try validateEXIdentity(deviceInformation)
        raw.append(.init(requestID: ELM327Command.extendedDeviceInformation.requestID, payload: deviceInformation))

        let vinResponse = try await channel.execute(ELM327Command.vehicleIdentificationNumber)
        try validate(vinResponse)
        raw.append(.init(requestID: ELM327Command.vehicleIdentificationNumber.requestID, payload: vinResponse))
        let identifier = try ELM327VehicleIdentifierParser().parse(vinResponse)

        let protocolResponse = try await channel.execute(ELM327Command.protocolDescription)
        try validate(protocolResponse)
        raw.append(.init(requestID: ELM327Command.protocolDescription.requestID, payload: protocolResponse))

        return VehicleIdentificationSnapshot(
            vin: identifier.vin,
            obdIdentifier: identifier.obdIdentifier,
            fields: [
                .init(id: "adapter", label: "OBD Adapter", value: cleaned(deviceInformation), source: endpoint.displayName),
                .init(id: "obdProtocol", label: "OBD Protocol", value: cleaned(protocolResponse), source: endpoint.displayName)
            ],
            rawResponses: raw,
            observedAt: now()
        )
    }

    /// ELM/STNの明示的な失敗応答を成功として扱わないよう検証します。
    ///
    /// 責務: 1件のコマンド応答を既知の拒否語と空応答に対して検証します。
    /// - Parameter response: プロンプトを除いた加工前応答。
    /// - Throws: 空、疑問符、NO DATA、BUS/CAN ERRORの場合は `VehicleIdentificationError.commandRejected`。
    private func validate(_ response: String) throws {
        let normalized = cleaned(response).uppercased()
        let rejected = ["?", "NO DATA", "UNABLE TO CONNECT", "BUS ERROR", "CAN ERROR", "STOPPED"]
        guard !normalized.isEmpty, !rejected.contains(where: normalized.contains) else {
            throw VehicleIdentificationError.commandRejected
        }
    }

    /// 拡張デバイス情報がOBDLink EX自身の応答であることを確認します。
    ///
    /// 責務: 1件の `STDIX` 応答をEX製品識別行の存在で検証します。
    /// - Parameter response: `STDIX` の加工前応答。
    /// - Throws: EX製品名を確認できない場合は `VehicleIdentificationError.transportUnsupported`。
    private func validateEXIdentity(_ response: String) throws {
        try validate(response)
        guard response.localizedCaseInsensitiveContains("Device: OBDLink EX") else {
            throw VehicleIdentificationError.transportUnsupported
        }
    }

    /// 表示用応答から制御用空白だけを整理します。
    ///
    /// 責務: 1件のアダプター応答を単一行の表示値へ縮約します。
    /// - Parameter response: 加工前応答。
    /// - Returns: 空白区切りの表示用文字列。
    private func cleaned(_ response: String) -> String {
        response.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }
}
