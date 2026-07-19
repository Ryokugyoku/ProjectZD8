import Foundation

/// 検証済み主要PID定義を実車応答へ適用します。
struct ReadMajorOBDPIDsUseCase {
    /// 読取対象とする検証済み定義です。
    private let definitions: [OBDPIDDefinition]
    /// 実車から未加工PIDバイトを取得する境界です。
    private let telemetry: any OBDPIDTelemetryPort
    /// 制限付き数式を適用する評価器です。
    private let evaluator: OBDPIDFormulaEvaluator
    /// 観測完了日時を供給するクロックです。
    private let now: @Sendable () -> Date

    /// 主要PID定義、実車読取境界、評価器を固定します。
    ///
    /// 責務: 検証済みPID定義群を1回の実車数値化処理へ結び付けます。
    /// - Parameters:
    ///   - definitions: 読み取る検証済みPID定義。
    ///   - telemetry: 未加工PIDバイトの取得境界。
    ///   - evaluator: 定義式の評価器。
    ///   - now: 観測完了日時の供給元。
    init(
        definitions: [OBDPIDDefinition],
        telemetry: any OBDPIDTelemetryPort,
        evaluator: OBDPIDFormulaEvaluator = .init(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.definitions = definitions
        self.telemetry = telemetry
        self.evaluator = evaluator
        self.now = now
    }

    /// 全主要PIDを1回読み取り、定義式で数値化します。
    ///
    /// 責務: 1回のOBD接続から全検証済み主要PIDの数値観測を生成します。
    /// - Parameter endpoint: OBDアダプターの物理終端。
    /// - Returns: 定義順の数値化済みPID観測。
    /// - Throws: 実車読取、応答不足、または数式評価に失敗した場合のエラー。
    func execute(using endpoint: OBDConnectionEndpoint) async throws -> [OBDPIDSample] {
        let requests = definitions.map { OBDPIDRequest(service: $0.service, pid: $0.pid) }
        let responses = try await telemetry.read(requests, using: endpoint)
        let observedAt = now()
        return try definitions.map { definition in
            let request = OBDPIDRequest(service: definition.service, pid: definition.pid)
            guard let bytes = responses[request] else { throw OBDPIDTelemetryError.incompleteResponse }
            return OBDPIDSample(
                request: request,
                nameKey: definition.nameKey,
                value: try evaluator.evaluate(definition, bytes: bytes),
                unit: definition.unit,
                observedAt: observedAt
            )
        }
    }
}
