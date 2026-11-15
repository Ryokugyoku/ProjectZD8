import Foundation

/// 常駐リンク上のELM/STNアダプターを初期化し、チップ種別とATMA対応可否を判定します。
///
/// 送るコマンド列(待機上限は `AdapterLinkELMCommandTimeouts`):
/// `ATZ` → `ATE0` → `ATL0` → `ATS1` → `ATH0` → `ATSP0` → `STI` → `ATI` → (必要時)`ATPPS`
/// → `ATH1` → `ATMA`(時間窓の受信を集め、プロンプトが無ければ `\r` で停止)→ `ATH0`。
/// 受信監視は判定後に必ず止め、ヘッダー表示を戻してアダプターを通常のコマンド待ちへ戻します。
/// 取得モード(PIDポーリング)は切り替えません。
@MainActor
final class AdapterLinkELMInitializer: AdapterLinkInitializationPort {
    /// 初期化で送る設定コマンドと待機上限です。
    private static let configurationCommands: [(ELM327Command, Duration)] = [
        (.reset, AdapterLinkELMCommandTimeouts.reset),
        (.echoOff, AdapterLinkELMCommandTimeouts.configuration),
        (.linefeedsOff, AdapterLinkELMCommandTimeouts.configuration),
        (.spacesOn, AdapterLinkELMCommandTimeouts.configuration),
        (.headersOff, AdapterLinkELMCommandTimeouts.configuration),
        (.automaticProtocol, AdapterLinkELMCommandTimeouts.configuration)
    ]

    /// 常駐リンクの受信を引き受けるバイトストリームです。
    private let stream: AdapterLinkByteStream
    /// 識別応答からチップ種別を決める方針です。
    private let chipClassification = OBDAdapterChipClassificationPolicy()
    /// 受信監視の応答を分類する型です。
    private let monitorClassifier = ELM327MonitorResponseClassifier()

    /// バイトストリームを固定して生成します。
    ///
    /// 責務: 初期化の送受信先を1本の常駐リンクへ結び付けます。
    /// - Parameter stream: 常駐リンクの受信を引き受けるバイトストリーム。
    init(stream: AdapterLinkByteStream) {
        self.stream = stream
    }

    /// アダプターを初期化して判定結果を返します。
    ///
    /// 責務: 占有権を取得している間に設定・チップ判定・ATMA判定を順に行い、1件の証拠値にまとめます。
    /// - Returns: チップ種別とATMA判定結果。判定できないチップは `.unknown`。
    /// - Throws: 占有・送受信の `AdapterLinkByteStreamError`、設定コマンドの拒否 `AdapterLinkELMCommandError`、キャンセル。
    func initializeAdapter() async throws -> AcquisitionAdapterProbeEvidence {
        try await AdapterLinkELMCommandSession.perform(on: stream) { session in
            try await configure(using: session)
            let chipFamily = try await classifyChip(using: session)
            let monitorOutcome = try await probeMonitor(using: session)
            return AcquisitionAdapterProbeEvidence(chipFamily: chipFamily, monitorProbeOutcome: monitorOutcome)
        }
    }

    /// 設定コマンドを順に送ります。
    ///
    /// 責務: リセットから自動プロトコル選択までを送り、いずれかの拒否を失敗にします。
    /// - Parameter session: 占有中の手続き。
    /// - Throws: 送受信エラーまたは拒否。
    private func configure(using session: AdapterLinkELMCommandSession) async throws {
        for (command, timeout) in Self.configurationCommands {
            _ = try await session.executeAccepted(command, timeout: timeout)
        }
    }

    /// 識別応答からチップ種別を判定します。
    ///
    /// 責務: `STI`・`ATI` と、方針が求める場合だけ `ATPPS` を送り、結果を判定方針へ渡します。
    /// `STI`・`ATPPS` の `?` は判定材料なので失敗にしません。
    /// - Parameter session: 占有中の手続き。
    /// - Returns: 判定したチップ種別。
    /// - Throws: 送受信エラー。
    private func classifyChip(using session: AdapterLinkELMCommandSession) async throws -> OBDAdapterChipFamily {
        let stnResponse = try await session.execute(ELM327Command.stnIdentity, timeout: AdapterLinkELMCommandTimeouts.identity)
        let identityResponse = try await session.execute(ELM327Command.adapterIdentity, timeout: AdapterLinkELMCommandTimeouts.identity)
        var extendedProbeAccepted: Bool?
        if chipClassification.requiresExtendedProbe(stnIdentityResponse: stnResponse, identityResponse: identityResponse) {
            let probeResponse = try await session.execute(
                ELM327Command.programmableParameterSummary,
                timeout: AdapterLinkELMCommandTimeouts.identity
            )
            extendedProbeAccepted = Self.isAccepted(probeResponse)
        }
        return chipClassification.classify(
            stnIdentityResponse: stnResponse,
            identityResponse: identityResponse,
            extendedProbeAccepted: extendedProbeAccepted
        )
    }

    /// ATMAの受信監視を試して結果を分類し、監視を止めて通常状態へ戻します。
    ///
    /// 責務: ヘッダー表示を有効にして `ATMA` を時間窓だけ試し、停止とヘッダー表示の復帰を確認してから分類結果を返します。
    /// - Parameter session: 占有中の手続き。
    /// - Returns: 受信監視の試行結果。
    /// - Throws: 送受信エラー(停止後のプロンプトが期限内に来ない場合を含む)、`ATH1`/`ATH0` の拒否。
    private func probeMonitor(using session: AdapterLinkELMCommandSession) async throws -> OBDMonitorProbeOutcome {
        _ = try await session.executeAccepted(ELM327Command.headersOn, timeout: AdapterLinkELMCommandTimeouts.configuration)
        let received = try await session.monitor(
            ELM327Command.monitorAll,
            window: AdapterLinkELMCommandTimeouts.monitorWindow,
            stopTimeout: AdapterLinkELMCommandTimeouts.monitorStop
        )
        _ = try await session.executeAccepted(ELM327Command.headersOff, timeout: AdapterLinkELMCommandTimeouts.configuration)
        return monitorClassifier.classify(received.components(separatedBy: CharacterSet(charactersIn: "\r\n")))
    }

    /// 追加プローブが受け付けられたかどうかを判定します。
    ///
    /// 責務: 空でなく `?` でない応答を受け付けとします。
    /// - Parameter response: 追加プローブの加工前応答。
    /// - Returns: 受け付けられたなら `true`。
    private static func isAccepted(_ response: String) -> Bool {
        !ELM327ResponseLines.normalizedLines(of: response).isEmpty && !ELM327ResponseLines.isRejection(response)
    }
}
