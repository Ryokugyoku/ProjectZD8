import Foundation

/// manifest作成をRaw開始前に停止するApplication上の理由です。
nonisolated enum CreateConnectionSessionAcquisitionManifestError: Error, Equatable, Sendable {
    /// 要求が現在のpolling世代に属していません。
    case inactiveGeneration
    /// 同じService/PIDのcapability入力が重複しています。
    case duplicateCapabilityEvidence
    /// PID定義に対応するcapability入力がありません。
    case capabilityEvidenceMissing
    /// capability入力に対応するPID定義がありません。
    case pidDefinitionEvidenceMissing
    /// revision、byte数、formula、unitのいずれかが完全ではありません。
    case incompletePIDDefinition
    /// validity rangeの片側だけが存在します。
    case incompleteValidityRange
}
