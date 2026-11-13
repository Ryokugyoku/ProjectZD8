/// PIDテーブルの定義を使って未加工応答バイトを意味のある数値へ変換します。
struct DecodeOBDPIDValueUseCase {
    /// 定義を取得する永続化境界です。
    private let repository: any OBDPIDDefinitionRepository
    /// 制限付き数式の評価器です。
    private let evaluator: OBDPIDFormulaEvaluator

    /// PID定義リポジトリと式評価器を注入して生成します。
    ///
    /// 責務: PID定義取得と数値評価の交換可能な境界を固定します。
    /// - Parameters:
    ///   - repository: Service/PID定義の取得先。
    ///   - evaluator: 保存式を応答バイトへ適用する評価器。
    init(repository: any OBDPIDDefinitionRepository, evaluator: OBDPIDFormulaEvaluator = .init()) {
        self.repository = repository
        self.evaluator = evaluator
    }

    /// 登録済みPID式を未加工応答バイトへ適用します。
    ///
    /// 責務: 1件のService/PID応答を登録定義に基づく数値と単位へ変換します。
    /// - Parameters:
    ///   - service: OBD Service番号。
    ///   - pid: Service内PID番号。
    ///   - bytes: ServiceとPIDを除いた未加工応答バイト。
    /// - Returns: 計算済み数値と定義単位。定義がなければ `nil`。
    /// - Throws: 定義取得または数式評価に失敗した場合のエラー。
    func execute(service: UInt8, pid: UInt8, bytes: [UInt8]) throws -> (value: Double, unit: String)? {
        guard let definition = try repository.definition(service: service, pid: pid) else { return nil }
        return (try evaluator.evaluate(definition, bytes: bytes), definition.unit)
    }
}
