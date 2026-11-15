import Foundation

/// Production取得loopが永続取得証拠を開始するための確定済み入力です。
nonisolated struct LiveTelemetryAcquisitionStartInput: Sendable {
    /// 取得loopが所有する世代です。
    let generation: UInt
    /// manifestへ固定する取得時PID定義です。
    let definitions: [OBDPIDDefinition]
    /// PID定義ごとの確認済みcapabilityと収集選択です。
    let capabilities: [ConnectionSessionAcquisitionPIDCapabilityInput]
    /// polling policyが基準tickで確定した要求順です。
    let orderedRequests: [OBDPIDRequest]
    /// 初期化時に判定したアダプターのチップ種別とATMA判定結果です。判定結果がない場合は `nil` です。
    let adapterProbeEvidence: AcquisitionAdapterProbeEvidence?

    /// 取得開始に必要な証拠入力を固定します。
    ///
    /// 責務: 1世代の定義、capability、要求順、アダプター判定結果をmanifest開始入力へまとめます。
    /// - Parameters:
    ///   - generation: 取得loopが所有する世代。
    ///   - definitions: manifestへ固定する取得時PID定義。
    ///   - capabilities: PID定義ごとの確認済みcapabilityと収集選択。
    ///   - orderedRequests: polling policyが確定した基準要求順。
    ///   - adapterProbeEvidence: 初期化時に判定したアダプター判定結果。判定結果がない場合は `nil`。
    init(
        generation: UInt,
        definitions: [OBDPIDDefinition],
        capabilities: [ConnectionSessionAcquisitionPIDCapabilityInput],
        orderedRequests: [OBDPIDRequest],
        adapterProbeEvidence: AcquisitionAdapterProbeEvidence? = nil
    ) {
        self.generation = generation
        self.definitions = definitions
        self.capabilities = capabilities
        self.orderedRequests = orderedRequests
        self.adapterProbeEvidence = adapterProbeEvidence
    }
}

