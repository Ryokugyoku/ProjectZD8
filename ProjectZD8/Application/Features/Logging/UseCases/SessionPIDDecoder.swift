import Foundation

/// セッションに固定した変換規則で応答を物理値へ変換します。
nonisolated struct SessionPIDDecoder: Sendable {
    /// 範囲判定の許容誤差です(式の丸め差を吸収します)。
    private static let rangeTolerance = 1e-6

    /// 責務: 構造だけを持つ変換器を生成します。
    init() {}

    /// 責務: 1件の要求結果を、有効値・範囲外・変換失敗・無応答のいずれかへ分類します。
    func decode(_ pid: SessionPID, result: OBDQueryResult) -> AcquisitionEvent.Reading {
        guard result.outcome == .responded else { return .noResponse(result.outcome) }
        let definition = OBDPIDDefinition(
            service: pid.request.service,
            pid: pid.request.pid,
            header: pid.header,
            nameKey: "",
            requiredByteCount: pid.requiredByteCount,
            formula: pid.formula,
            unit: pid.unit,
            minimumValue: pid.minimumValue,
            maximumValue: pid.maximumValue,
            sourceURI: "",
            revision: pid.definitionRevision
        )
        guard let value = try? OBDPIDFormulaEvaluator().evaluate(definition, bytes: result.payload) else {
            return .decodeFailed
        }
        if let minimum = pid.minimumValue, value < minimum - Self.rangeTolerance { return .outOfRange(value) }
        if let maximum = pid.maximumValue, value > maximum + Self.rangeTolerance { return .outOfRange(value) }
        return .value(value)
    }
}
