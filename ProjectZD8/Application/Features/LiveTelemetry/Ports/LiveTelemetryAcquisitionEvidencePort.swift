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

    /// 取得開始に必要な証拠入力を固定します。
    ///
    /// 責務: 1世代の定義、capability、要求順をmanifest開始入力へまとめます。
    /// - Parameters:
    ///   - generation: 取得loopが所有する世代。
    ///   - definitions: manifestへ固定する取得時PID定義。
    ///   - capabilities: PID定義ごとの確認済みcapabilityと収集選択。
    ///   - orderedRequests: polling policyが確定した基準要求順。
    init(
        generation: UInt,
        definitions: [OBDPIDDefinition],
        capabilities: [ConnectionSessionAcquisitionPIDCapabilityInput],
        orderedRequests: [OBDPIDRequest]
    ) {
        self.generation = generation
        self.definitions = definitions
        self.capabilities = capabilities
        self.orderedRequests = orderedRequests
    }
}

/// Production取得loopが1 batchを方式Bで保存するための確定済み入力です。
nonisolated struct LiveTelemetryAcquisitionBatchInput: Sendable {
    /// 取得loopが所有する世代です。
    let generation: UInt
    /// session内で安定したbatch番号です。
    let batchOrdinal: Int64
    /// polling policyが評価したtickです。
    let policyTick: UInt
    /// batch開始を観測した実時間です。
    let startedAt: Date
    /// 250 ms sleepの予定wake時刻から実開始までの非負遅延です。
    let scheduleDelayNanoseconds: UInt64?
    /// 今回選択された順序付きPID定義です。
    let definitions: [OBDPIDDefinition]
    /// 物理要求に使用する終端です。
    let endpoint: OBDConnectionEndpoint

    /// 1回のpolling tickを永続batch入力へ固定します。
    ///
    /// 責務: batch identity、policy tick、schedule遅延、選択定義、終端を1件の取得要求へまとめます。
    /// - Parameters:
    ///   - generation: 取得loopが所有する世代。
    ///   - batchOrdinal: session内で安定したbatch番号。
    ///   - policyTick: polling policyが評価したtick。
    ///   - startedAt: batch開始を観測した実時間。
    ///   - scheduleDelayNanoseconds: tick 0では `nil`、後続tickでは予定wakeからの非負遅延。
    ///   - definitions: 今回選択された順序付きPID定義。
    ///   - endpoint: 物理要求に使用する終端。
    init(
        generation: UInt,
        batchOrdinal: Int64,
        policyTick: UInt,
        startedAt: Date,
        scheduleDelayNanoseconds: UInt64? = nil,
        definitions: [OBDPIDDefinition],
        endpoint: OBDConnectionEndpoint
    ) {
        self.generation = generation
        self.batchOrdinal = batchOrdinal
        self.policyTick = policyTick
        self.startedAt = startedAt
        self.scheduleDelayNanoseconds = scheduleDelayNanoseconds
        self.definitions = definitions
        self.endpoint = endpoint
    }
}

/// Production取得loopを方式BのApplication orchestrationへ接続する能力です。
nonisolated protocol LiveTelemetryAcquisitionEvidencePort: Sendable {
    /// manifestと開始境界を保存し、成功した世代だけを取得可能にします。
    ///
    /// 責務: 1世代の確定済み取得入力を物理要求許可へ変換します。
    /// - Parameter input: 定義、capability、policy順を含む取得開始入力。
    /// - Throws: session不在、入力不正、stale世代、または保存失敗。
    func start(_ input: LiveTelemetryAcquisitionStartInput) async throws

    /// 1回のpolling tickを方式Bで取得・保存して表示用sampleを返します。
    ///
    /// 責務: 1 batchの物理観測を原子保存済みRaw証拠と表示用sampleへ変換します。
    /// - Parameter input: stable ordinalとpolicy tickを持つbatch入力。
    /// - Returns: 同じ物理応答から生成した表示用sample。
    /// - Throws: stale世代、入力不正、通信後の永続化失敗、またはbatch確定失敗。
    func acquire(_ input: LiveTelemetryAcquisitionBatchInput) async throws -> [OBDPIDSample]

    /// 指定世代からの新しい証拠作成を停止します。
    ///
    /// 責務: 1世代のmanifestとbatch orchestrationをstale状態へ遷移させます。
    /// - Parameter generation: 停止する取得世代。
    func cancel(generation: UInt) async
}
