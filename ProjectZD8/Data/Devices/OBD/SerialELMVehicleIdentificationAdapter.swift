import Foundation

/// 選択済みELM/STN互換バイトストリームへ型付きコマンドだけを送り車両識別子を取得します。
struct SerialELMVehicleIdentificationAdapter: VehicleIdentificationPort {
    /// ELM/STNバイトストリームTransportを生成するFactoryです。
    private let makeTransport: @MainActor @Sendable (OBDConnectionEndpoint) throws -> any OBDCommandTransport
    /// 観測日時を提供する注入済みクロックです。
    private let now: @Sendable () -> Date

    /// Transport Factoryとクロックを注入して生成します。
    ///
    /// 責務: ELM/STN車両識別処理を物理Transport生成と時刻取得境界へ固定します。
    /// - Parameters:
    ///   - makeTransport: 接続終端に対応するTransport生成処理。
    ///   - now: 観測完了日時の供給元。
    init(
        makeTransport: @escaping @MainActor @Sendable (OBDConnectionEndpoint) throws -> any OBDCommandTransport,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.makeTransport = makeTransport
        self.now = now
    }

    /// 選択済みELM/STNアダプターを初期化してService 09 PID 02の車両識別子を取得します。
    ///
    /// 責務: 1件の選択済みELM/STN接続から型付き読取専用識別観測を生成します。
    /// - Parameter endpoint: 選択済みアダプターが公開する連続バイトストリーム終端。
    /// - Returns: VIN、アダプター、プロトコル、加工前応答を含む観測。
    /// - Throws: 非シリアル終端、接続、コマンド、応答解析に失敗した場合の識別エラー。
    func identifyVehicle(using endpoint: OBDConnectionEndpoint) async throws -> VehicleIdentificationSnapshot {
        guard endpoint.transport.supportsELMByteStream else {
            throw VehicleIdentificationError.stageFailed(.endpointValidation, .transportUnsupported)
        }
        let transport: any OBDCommandTransport
        do {
            transport = try makeTransport(endpoint)
        } catch {
            throw staged(error, at: .transportCreation)
        }
        do {
            do {
                try await transport.open()
            } catch {
                throw staged(error, at: .transportOpen)
            }
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
    /// 責務: 1件の開かれたシリアルチャネルへ承認済み識別コマンド列を適用します。
    /// - Parameters:
    ///   - channel: 単一inflightを保証するELMコマンドチャネル。
    ///   - endpoint: 表示用アダプター情報を持つ接続終端。
    /// - Returns: VINと全原文応答を保持する観測。
    /// - Throws: いずれかのコマンドまたはVIN解析に失敗した場合のエラー。
    private func identify(using channel: SerializedELMCommandChannel, endpoint: OBDConnectionEndpoint) async throws -> VehicleIdentificationSnapshot {
        var raw: [VehicleIdentificationSnapshot.RawResponse] = []
        for command in [ELM327Command.reset] {
            let response = try await execute(command, at: .adapterReset, using: channel)
            raw.append(.init(requestID: command.requestID, payload: response))
        }
        for command in [.echoOff, .linefeedsOff, .spacesOn, .headersOff, .automaticProtocol] as [ELM327Command] {
            let response = try await execute(command, at: .adapterConfiguration, using: channel)
            raw.append(.init(requestID: command.requestID, payload: response))
        }
        let adapterResponse = try await execute(.adapterIdentity, at: .adapterIdentity, using: channel)
        raw.append(.init(requestID: ELM327Command.adapterIdentity.requestID, payload: adapterResponse))

        let vinResponse = try await execute(.vehicleIdentificationNumber, at: .vehicleIdentificationRequest, using: channel)
        raw.append(.init(requestID: ELM327Command.vehicleIdentificationNumber.requestID, payload: vinResponse))
        let identifier: ELM327VehicleIdentifierParser.Result
        do {
            identifier = try ELM327VehicleIdentifierParser().parse(vinResponse)
        } catch {
            throw staged(error, at: .vehicleIdentificationParsing)
        }

        let protocolResponse = try await execute(.protocolDescription, at: .protocolDescription, using: channel)
        raw.append(.init(requestID: ELM327Command.protocolDescription.requestID, payload: protocolResponse))

        return VehicleIdentificationSnapshot(
            vin: identifier.vin,
            obdIdentifier: identifier.obdIdentifier,
            fields: [
                .init(id: "adapter", label: "OBD Adapter", value: cleaned(adapterResponse), source: endpoint.displayName),
                .init(id: "obdProtocol", label: "OBD Protocol", value: cleaned(protocolResponse), source: endpoint.displayName)
            ],
            rawResponses: raw,
            observedAt: now()
        )
    }

    /// 1件の型付きコマンドを実行して失敗へ識別段階を付与します。
    ///
    /// 責務: 単一コマンドの送受信と既知拒否応答の検証を指定段階へ結び付けます。
    /// - Parameters:
    ///   - command: 実行する許可済みコマンド。
    ///   - stage: コマンド失敗時に保持する識別段階。
    ///   - channel: 単一inflightを保証するELMコマンドチャネル。
    /// - Returns: 検証済みの加工前応答。
    /// - Throws: 段階と原因を保持した `VehicleIdentificationError.stageFailed`。
    private func execute(
        _ command: ELM327Command,
        at stage: VehicleIdentificationError.Stage,
        using channel: SerializedELMCommandChannel
    ) async throws -> String {
        do {
            let response = try await channel.execute(command)
            try validate(response)
            return response
        } catch {
            throw staged(error, at: stage)
        }
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

    /// 下位境界の失敗を識別段階と単一原因を持つエラーへ変換します。
    ///
    /// 責務: 1件の下位エラーを指定された車両識別段階へ関連付けます。
    /// - Parameters:
    ///   - error: Transport、チャネル、検証、解析のいずれかが返したエラー。
    ///   - stage: 失敗時に実行していた単一段階。
    /// - Returns: 段階と表示可能な原因を保持する型付き識別エラー。
    private func staged(
        _ error: Error,
        at stage: VehicleIdentificationError.Stage
    ) -> VehicleIdentificationError {
        guard let identificationError = error as? VehicleIdentificationError else {
            return .stageFailed(stage, .unavailable)
        }
        switch identificationError {
        case let .stageFailed(existingStage, cause):
            return .stageFailed(existingStage, cause)
        case .unavailable, .pidCatalogUnavailable, .vinUnavailable:
            return .stageFailed(stage, .unavailable)
        case .transportUnsupported:
            return .stageFailed(stage, .transportUnsupported)
        case .connectionFailed:
            return .stageFailed(stage, .connectionFailed)
        case .responseTimedOut:
            return .stageFailed(stage, .responseTimedOut)
        case .commandRejected:
            return .stageFailed(stage, .commandRejected)
        case .malformedResponse:
            return .stageFailed(stage, .malformedResponse)
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
