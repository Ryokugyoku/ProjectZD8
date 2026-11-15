import Foundation
@testable import ProjectZD8

/// 固定のアプリ版・スキーマ版・取得端末を返す実行環境証拠のフェイクです。
struct FixedRuntimeEvidencePort: ConnectionSessionAcquisitionEvidencePort {
    /// 固定の実行環境証拠を返します。
    ///
    /// 責務: manifest作成を実環境に依存しない決定的な版情報へ変換します。
    /// - Returns: 単位2テスト用の実行環境証拠。
    func evidence() async throws -> ConnectionSessionAcquisitionRuntimeEvidence {
        ConnectionSessionAcquisitionRuntimeEvidence(
            applicationVersion: try AcquisitionApplicationVersion(marketingVersion: "unit2", buildVersion: "test"),
            schemaContractVersion: 1,
            acquisitionPlatform: .macOS
        )
    }
}
