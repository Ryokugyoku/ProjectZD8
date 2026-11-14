import Foundation
@testable import ProjectZD8

/// 固定のapp・build・schema・platformを返す取得runtime証拠の境界です。
struct FixedAcquisitionRuntimeEvidencePort: ConnectionSessionAcquisitionEvidencePort {
    /// 固定の証拠で生成します。
    ///
    /// 責務: 実環境に依存しない決定的なversion証拠の境界を構築します。
    init() {}

    /// 固定のruntime証拠を返します。
    ///
    /// 責務: manifest作成へ固定のversion証拠を渡します。
    /// - Returns: テスト用のruntime証拠。
    /// - Throws: appのversion値が不正な場合のエラー。
    func evidence() async throws -> ConnectionSessionAcquisitionRuntimeEvidence {
        ConnectionSessionAcquisitionRuntimeEvidence(
            applicationVersion: try AcquisitionApplicationVersion(marketingVersion: "1", buildVersion: "1"),
            schemaContractVersion: 1,
            acquisitionPlatform: .macOS
        )
    }
}
