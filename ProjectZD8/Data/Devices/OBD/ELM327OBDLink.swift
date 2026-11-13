import Foundation

/// 1本のバイトストリームTransport上で動くELM327互換アダプターのOBDリンクです。要求は常に1件ずつ直列に処理します。
///
/// 読み取り専用です。サービス01(標準PID)とサービス21(車種専用PID)以外は送信せず `.failed` として返します。
actor ELM327OBDLink: OBDLink {
    /// 機能アドレス(全ECUへの標準要求)の11bit CAN IDです。
    private static let functionalAddress: UInt16 = 0x7DF
    /// 初期化で順に送るATコマンドです。
    private static let initializationCommands = ["ATZ", "ATE0", "ATL0", "ATS1", "ATH0", "ATSP0"]
    /// 設定系コマンドの応答を拒否とみなす語です。
    private static let rejectionTokens = ["?", "ERROR", "UNABLE", "OUT OF MEMORY", "NO DATA", "STOPPED", "BUFFER FULL"]

    /// 通信の物理終端です。
    private let transport: any OBDCommandTransport
    /// 識別情報の観測日時を供給します。
    private let now: @Sendable () -> Date
    /// 現在ELMへ設定している送信ヘッダーです。不明なら `nil` です。
    private var activeHeader: UInt16?
    /// 通信が壊れた、または閉じた後は `true` です。以後の呼び出しは `connectionLost` になります。
    private var isUnavailable = false

    /// Transportを開いて初期化まで済ませたリンクを返します。
    ///
    /// 責務: 1件のTransportを開き、ATZからATSP0までの初期化を終えた直列リンクを構築します。
    /// - Parameters:
    ///   - transport: まだ開いていないバイトストリームTransport。
    ///   - now: 観測日時の供給元。
    /// - Throws: 開通失敗は `connectionFailed`/`transportUnsupported`、初期化中の拒否は `adapterRejected`、タイムアウトは `timedOut`。失敗時はTransportを閉じます。
    static func connect(
        transport: any OBDCommandTransport,
        now: @escaping @Sendable () -> Date = Date.init
    ) async throws -> ELM327OBDLink {
        do {
            try await transport.open()
        } catch let error as OBDTransportError where error == .transportUnsupported {
            throw OBDLinkError.transportUnsupported
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw OBDLinkError.connectionFailed
        }
        let link = ELM327OBDLink(transport: transport, now: now)
        do {
            try await link.initialize()
        } catch {
            await transport.close()
            throw error
        }
        return link
    }

    /// 責務: 開通済みTransportを保持するリンクを生成します。初期化は `connect` が行います。
    private init(transport: any OBDCommandTransport, now: @escaping @Sendable () -> Date) {
        self.transport = transport
        self.now = now
    }

    /// 責務: アダプター情報(ATI)、VIN(0902)、プロトコル(ATDP)を読み取ります。
    /// - Throws: VIN無応答は `vinUnavailable`、通信断は `connectionLost`、無応答は `timedOut`、想定外の応答は `adapterRejected`。
    func identify() async throws -> VehicleIdentification {
        let adapterResponse = try await sendSetting("ATI")
        try await ensureHeader(Self.functionalAddress)
        let vinResponse = try await sendRaw("0902")
        guard !vinResponse.uppercased().contains("NO DATA"),
              let vin = ELM327VINParser().parse(vinResponse) else {
            throw OBDLinkError.vinUnavailable
        }
        let protocolResponse = try await sendSetting("ATDP")
        return VehicleIdentification(
            vin: vin,
            adapterDescription: cleaned(adapterResponse),
            protocolDescription: cleaned(protocolResponse),
            observedAt: now()
        )
    }

    /// 責務: サービス01の対応ビットマップ(00/20/40/…)を辿り、車両が対応するデータPIDを返します。
    /// - Throws: 最初の範囲に応答が無い場合は `timedOut`、解釈できない場合は `adapterRejected`、通信断は `connectionLost`。
    func supportedPIDs() async throws -> Set<OBDPIDRequest> {
        var supported: Set<OBDPIDRequest> = []
        var base: UInt8 = 0x00
        while true {
            let result = try await query(OBDPIDRequest(service: 0x01, pid: base), header: nil)
            switch result.outcome {
            case .responded:
                guard let bitmap = ELM327SupportBitmap(base: base, payload: result.payload) else {
                    throw OBDLinkError.adapterRejected
                }
                supported.formUnion(bitmap.supportedPIDs.map { OBDPIDRequest(service: 0x01, pid: $0) })
                guard bitmap.hasNextRange else { return supported }
                base += 0x20
            case .noData:
                if base == 0x00 { throw OBDLinkError.timedOut }
                return supported
            case .timedOut:
                throw OBDLinkError.timedOut
            case .failed:
                throw OBDLinkError.adapterRejected
            }
        }
    }

    /// 責務: 1件のPIDを送り、応答を `OBDQueryResult` へ分類します。
    /// - Throws: 通信が壊れた場合の `connectionLost` だけです。無応答・NO DATA・不正応答は結果として返します。
    func query(_ request: OBDPIDRequest, header: UInt16?) async throws -> OBDQueryResult {
        try ensureAvailable()
        let targetHeader: UInt16
        switch request.service {
        case 0x01:
            targetHeader = header ?? Self.functionalAddress
        case 0x21:
            guard let header else { return OBDQueryResult(outcome: .failed) }
            targetHeader = header
        default:
            return OBDQueryResult(outcome: .failed)
        }
        guard targetHeader <= 0x7FF else { return OBDQueryResult(outcome: .failed) }

        do {
            do {
                try await ensureHeader(targetHeader)
            } catch OBDLinkError.adapterRejected {
                return OBDQueryResult(outcome: .failed)
            } catch OBDLinkError.timedOut {
                return OBDQueryResult(outcome: .timedOut)
            }
            let response = try await sendRaw(String(format: "%02X%02X", request.service, request.pid))
            let first = classify(response, for: request)
            guard let first else {
                // 直前のタイムアウトの遅延応答だった。読み捨てて今回の応答を1回だけ読み直す。
                return classify(try await readResponse(), for: request) ?? OBDQueryResult(outcome: .failed)
            }
            return first
        } catch OBDLinkError.timedOut {
            return OBDQueryResult(outcome: .timedOut)
        }
    }

    /// 責務: 1件の応答を結果へ分類します。別要求への正応答(遅延応答)の場合は `nil` を返します。
    private func classify(_ response: String, for request: OBDPIDRequest) -> OBDQueryResult? {
        switch ELM327ResponseParser().parse(response, request: request) {
        case let .data(payload): OBDQueryResult(outcome: .responded, payload: payload)
        case .noData: OBDQueryResult(outcome: .noData)
        case .rejected, .unrecognized: OBDQueryResult(outcome: .failed)
        case .otherResponse: nil
        }
    }

    /// 責務: Transportを閉じ、以後の要求を `connectionLost` にします。
    func close() async {
        guard !isUnavailable else { return }
        isUnavailable = true
        await transport.close()
    }

    /// 責務: ATZからATSP0までの初期化コマンドを順に送り、拒否応答なら失敗します。
    private func initialize() async throws {
        for command in Self.initializationCommands {
            _ = try await sendSetting(command)
        }
    }

    /// 責務: 現在値と異なる場合だけ `ATSH` で送信ヘッダーを切り替えます。
    /// - Throws: ELMが拒否した場合は `adapterRejected`。
    private func ensureHeader(_ header: UInt16) async throws {
        guard activeHeader != header else { return }
        activeHeader = nil
        _ = try await sendSetting(String(format: "ATSH%03X", header))
        activeHeader = header
    }

    /// 責務: 設定系コマンドを送り、空応答や既知の拒否語を `adapterRejected` として扱います。
    private func sendSetting(_ command: String) async throws -> String {
        let response = try await sendRaw(command)
        let normalized = response.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalized.isEmpty, !Self.rejectionTokens.contains(where: normalized.contains) else {
            throw OBDLinkError.adapterRejected
        }
        return response
    }

    /// 責務: 1件のコマンドを書き込み、次のプロンプトまでの応答文字列を返します。
    /// - Throws: Transportの失敗は `connectionLost`(以後リンクは使用不可)、読取期限切れは `timedOut`。
    private func sendRaw(_ command: String) async throws -> String {
        try ensureAvailable()
        do {
            try await transport.write(Data((command + "\r").utf8))
        } catch {
            throw breakLink(error)
        }
        return try await readResponse()
    }

    /// 責務: 次のプロンプトまでの応答を読み、`>` を除いた文字列にします。
    private func readResponse() async throws -> String {
        let data: Data
        do {
            data = try await transport.readUntilPrompt()
        } catch let error as OBDTransportError where error == .timedOut {
            throw OBDLinkError.timedOut
        } catch {
            throw breakLink(error)
        }
        guard let response = String(data: data, encoding: .utf8) else { return "" }
        return response.replacingOccurrences(of: ">", with: "")
    }

    /// 責務: 通信が壊れたことを記録し、投げるべきエラーを返します。取消しは取消しのまま伝えます。
    private func breakLink(_ error: any Error) -> any Error {
        isUnavailable = true
        activeHeader = nil
        return error is CancellationError ? error : OBDLinkError.connectionLost
    }

    /// 責務: 通信が壊れている、または閉じている場合に `connectionLost` を投げます。
    private func ensureAvailable() throws {
        if isUnavailable { throw OBDLinkError.connectionLost }
    }

    /// 責務: 応答の空白と改行を1つのスペースへ整えて表示用文字列にします。
    private func cleaned(_ response: String) -> String {
        response.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }
}
