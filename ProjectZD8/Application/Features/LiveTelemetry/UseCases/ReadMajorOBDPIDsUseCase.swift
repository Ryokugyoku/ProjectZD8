import Dispatch
import Foundation

/// PID定義DBの現在一覧を実車応答へ適用します。
struct ReadMajorOBDPIDsUseCase {
    /// 読取対象を取得するPID定義永続化境界です。
    private let definitionRepository: any OBDPIDDefinitionRepository
    /// 実車から未加工PIDバイトを取得する境界です。
    private let telemetry: any OBDPIDTelemetryPort
    /// 制限付き数式を適用する評価器です。
    private let evaluator: OBDPIDFormulaEvaluator
    /// 観測完了日時を供給するクロックです。
    private let now: @Sendable () -> Date
    /// 要求バッチの単調経過時間を計測するクロックです。
    private let monotonicNanoseconds: @Sendable () -> UInt64
    /// 数値化前の応答をLoggingへ通知する処理です。
    private let rawResponseDidReceive: @Sendable (OBDRawResponseObservation) async throws -> Void

    /// PID定義Repository、実車読取境界、評価器を固定します。
    ///
    /// 責務: PID定義永続化境界を1回の実車数値化処理へ結び付けます。
    /// - Parameters:
    ///   - definitionRepository: 読取時点のPID定義一覧を返す永続化境界。
    ///   - telemetry: 未加工PIDバイトの取得境界。
    ///   - evaluator: 定義式の評価器。
    ///   - now: 観測完了日時の供給元。
    ///   - monotonicNanoseconds: 要求バッチ経過時間を計測する単調クロック。
    ///   - rawResponseDidReceive: 数値化前の応答をLoggingへ通知する処理。
    init(
        definitionRepository: any OBDPIDDefinitionRepository,
        telemetry: any OBDPIDTelemetryPort,
        evaluator: OBDPIDFormulaEvaluator = .init(),
        now: @escaping @Sendable () -> Date = Date.init,
        monotonicNanoseconds: @escaping @Sendable () -> UInt64 = { DispatchTime.now().uptimeNanoseconds },
        rawResponseDidReceive: @escaping @Sendable (OBDRawResponseObservation) async throws -> Void = { _ in }
    ) {
        self.definitionRepository = definitionRepository
        self.telemetry = telemetry
        self.evaluator = evaluator
        self.now = now
        self.monotonicNanoseconds = monotonicNanoseconds
        self.rawResponseDidReceive = rawResponseDidReceive
    }

    /// DB登録済みの全PID定義を読み込みます。
    ///
    /// 責務: 現在のPID定義永続化状態を空でない読取対象一覧へ変換します。
    /// - Returns: Service/PID順のPID定義一覧。
    /// - Throws: PID定義読込に失敗した場合または一覧が空の場合は `OBDPIDTelemetryError.definitionCatalogUnavailable`。
    func loadDefinitions() throws -> [OBDPIDDefinition] {
        let definitions: [OBDPIDDefinition]
        do {
            definitions = try definitionRepository.definitions()
        } catch {
            throw OBDPIDTelemetryError.definitionCatalogUnavailable
        }
        let decodable = definitions.filter(\.isDecodable)
        guard !decodable.isEmpty else {
            throw OBDPIDTelemetryError.definitionCatalogUnavailable
        }
        return decodable
    }

    /// 車両設定で収集有効な対応PIDに一致する数値化可能定義を読み込みます。
    ///
    /// 責務: 車両別収集選択を安全に数値化できるPID定義一覧へ変換します。
    /// - Parameter capabilities: 車両で確認済みの対応PID設定。
    /// - Returns: 収集有効かつ数式確認済みの定義一覧。
    /// - Throws: PIDカタログ読込に失敗した場合または対象が空の場合のエラー。
    func loadDefinitions(for capabilities: [VehiclePIDCapability]) throws -> [OBDPIDDefinition] {
        let enabled = Set(capabilities.filter(\.isCollectionEnabled).map(\.id.request))
        let definitions = try loadDefinitions().filter {
            enabled.contains(OBDPIDRequest(service: $0.service, pid: $0.pid))
        }
        guard !definitions.isEmpty else { throw OBDPIDTelemetryError.definitionCatalogUnavailable }
        return definitions
    }

    /// 指定PID定義を1回読み取り、応答済み項目だけを数値化します。
    ///
    /// 責務: 1回のOBD接続から応答があったPIDだけの数値観測を生成します。
    /// - Parameters:
    ///   - definitions: 今回照会するPID定義。
    ///   - endpoint: OBDアダプターの物理終端。
    /// - Returns: 入力定義順で並ぶ数値化済みPID観測。
    /// - Throws: 実車読取または応答済み値の数式評価に失敗した場合のエラー。
    func execute(
        definitions: [OBDPIDDefinition],
        using endpoint: OBDConnectionEndpoint
    ) async throws -> [OBDPIDSample] {
        let standardDefinitions = definitions.filter { !$0.isVehicleSpecific }
        let vehicleSpecificDefinitions = definitions.filter(\.isVehicleSpecific)
        let requests = standardDefinitions.map { OBDPIDRequest(service: $0.service, pid: $0.pid) }
        let startedAt = monotonicNanoseconds()
        var responses = requests.isEmpty ? [:] : try await telemetry.read(requests, using: endpoint)
        if !vehicleSpecificDefinitions.isEmpty {
            let vehicleResponses = try await telemetry.readVehicleSpecific(vehicleSpecificDefinitions, using: endpoint)
            responses.merge(vehicleResponses) { _, latest in latest }
        }
        let observedAt = now()
        let elapsed = monotonicNanoseconds() &- startedAt
        try await recordRawResponses(responses, observedAt: observedAt, elapsedNanoseconds: elapsed)
        return try definitions.compactMap { definition in
            let request = OBDPIDRequest(service: definition.service, pid: definition.pid)
            guard let bytes = responses[request] else { return nil }
            return OBDPIDSample(
                request: request,
                nameKey: definition.nameKey,
                value: try evaluator.evaluate(definition, bytes: bytes),
                unit: definition.unit,
                vehicleModelCode: definition.vehicleModelCode,
                observedAt: observedAt,
                summaryKey: definition.summaryKey,
                highValueKey: definition.highValueKey,
                lowValueKey: definition.lowValueKey,
                correlationKey: definition.correlationKey
            )
        }
    }

    /// 指定PID定義をアダプター管理の周期応答から数値化します。
    ///
    /// 責務: 1回の周期受信バッチを応答済みPIDの数値観測へ変換します。
    /// - Parameters:
    ///   - definitions: 周期取得する読取り専用PID定義。
    ///   - endpoint: OBDアダプターの物理終端。
    /// - Returns: 今回受信できた定義順の数値化済みPID観測。
    /// - Throws: 周期送信、受信、または数式評価に失敗した場合のエラー。
    func executePeriodic(
        definitions: [OBDPIDDefinition],
        using endpoint: OBDConnectionEndpoint
    ) async throws -> [OBDPIDSample] {
        let requests = definitions.map { OBDPIDRequest(service: $0.service, pid: $0.pid) }
        let startedAt = monotonicNanoseconds()
        let responses = try await telemetry.readPeriodic(requests, using: endpoint)
        let observedAt = now()
        let elapsed = monotonicNanoseconds() &- startedAt
        try await recordRawResponses(responses, observedAt: observedAt, elapsedNanoseconds: elapsed)
        return try definitions.compactMap { definition in
            let request = OBDPIDRequest(service: definition.service, pid: definition.pid)
            guard let bytes = responses[request] else { return nil }
            return OBDPIDSample(
                request: request,
                nameKey: definition.nameKey,
                value: try evaluator.evaluate(definition, bytes: bytes),
                unit: definition.unit,
                vehicleModelCode: definition.vehicleModelCode,
                observedAt: observedAt,
                summaryKey: definition.summaryKey,
                highValueKey: definition.highValueKey,
                lowValueKey: definition.lowValueKey,
                correlationKey: definition.correlationKey
            )
        }
    }

    /// DB登録済みの全PIDを1回読み取り、定義式で数値化します。
    ///
    /// 責務: 1回のOBD接続からDB登録済みPIDの応答済み数値観測を生成します。
    /// - Parameter endpoint: OBDアダプターの物理終端。
    /// - Returns: DBのService/PID順で並ぶ数値化済みPID観測。
    /// - Throws: PID定義読込、実車読取、または数式評価に失敗した場合のエラー。
    func execute(using endpoint: OBDConnectionEndpoint) async throws -> [OBDPIDSample] {
        try await execute(definitions: loadDefinitions(), using: endpoint)
    }

    /// 現在のPID通信セッションを終了します。
    ///
    /// 責務: 注入済みPID取得境界へ接続資源の終了を通知します。
    func endSession() async {
        await telemetry.endSession()
    }

    /// 応答辞書を数値化前のLogging観測として通知します。
    ///
    /// 責務: 1回の要求バッチ応答を安定したService/PID順のRaw観測へ変換します。
    /// - Parameters:
    ///   - responses: 取得境界が返した未デコード応答辞書。
    ///   - observedAt: 応答群を受け取った実時間。
    ///   - elapsedNanoseconds: 要求バッチ開始から応答群受信までの単調時間。
    /// - Throws: Logging保存境界がRaw応答を受理できない場合のエラー。
    private func recordRawResponses(
        _ responses: [OBDPIDRequest: [UInt8]],
        observedAt: Date,
        elapsedNanoseconds: UInt64
    ) async throws {
        for request in responses.keys.sorted(by: { ($0.service, $0.pid) < ($1.service, $1.pid) }) {
            guard let payload = responses[request] else { continue }
            try await rawResponseDidReceive(
                OBDRawResponseObservation(
                    observedAt: observedAt,
                    batchElapsedNanoseconds: elapsedNanoseconds,
                    request: request,
                    payload: payload
                )
            )
        }
    }
}
