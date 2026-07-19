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

    /// PID定義Repository、実車読取境界、評価器を固定します。
    ///
    /// 責務: PID定義永続化境界を1回の実車数値化処理へ結び付けます。
    /// - Parameters:
    ///   - definitionRepository: 読取時点のPID定義一覧を返す永続化境界。
    ///   - telemetry: 未加工PIDバイトの取得境界。
    ///   - evaluator: 定義式の評価器。
    ///   - now: 観測完了日時の供給元。
    init(
        definitionRepository: any OBDPIDDefinitionRepository,
        telemetry: any OBDPIDTelemetryPort,
        evaluator: OBDPIDFormulaEvaluator = .init(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.definitionRepository = definitionRepository
        self.telemetry = telemetry
        self.evaluator = evaluator
        self.now = now
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
        guard !definitions.isEmpty else {
            throw OBDPIDTelemetryError.definitionCatalogUnavailable
        }
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
        let requests = definitions.map { OBDPIDRequest(service: $0.service, pid: $0.pid) }
        let responses = try await telemetry.read(requests, using: endpoint)
        let observedAt = now()
        return try definitions.compactMap { definition in
            let request = OBDPIDRequest(service: definition.service, pid: definition.pid)
            guard let bytes = responses[request] else { return nil }
            return OBDPIDSample(
                request: request,
                nameKey: definition.nameKey,
                value: try evaluator.evaluate(definition, bytes: bytes),
                unit: definition.unit,
                observedAt: observedAt
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
}
