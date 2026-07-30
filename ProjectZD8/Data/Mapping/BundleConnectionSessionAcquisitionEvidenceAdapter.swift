import Foundation

/// Bundleと注入済みschema authorityから取得runtime evidenceを生成します。
nonisolated struct BundleConnectionSessionAcquisitionEvidenceAdapter: ConnectionSessionAcquisitionEvidencePort {
    /// version文字列を読むBundleです。
    private let bundle: Bundle
    /// GRDB readerが解釈するschema契約versionです。
    private let schemaContractVersion: Int
    /// 端末名を含まない現在platformです。
    private let acquisitionPlatform: ConnectionSessionAcquisitionPlatform

    /// Bundle、schema version、platform authorityを固定します。
    ///
    /// 責務: Production runtime evidenceの3つのauthorityを1件のadapterへ注入します。
    /// - Parameters:
    ///   - bundle: marketing versionとbuild versionを読むBundle。
    ///   - schemaContractVersion: GRDB readerが解釈するschema契約version。
    ///   - acquisitionPlatform: 端末名を含まない現在platform。
    init(
        bundle: Bundle = .main,
        schemaContractVersion: Int,
        acquisitionPlatform: ConnectionSessionAcquisitionPlatform
    ) {
        self.bundle = bundle
        self.schemaContractVersion = schemaContractVersion
        self.acquisitionPlatform = acquisitionPlatform
    }

    /// Bundleのversionと注入済みschema/platformを返します。
    ///
    /// 責務: 現在processのversion情報をmanifest用runtime evidenceへ変換します。
    /// - Returns: app/build、schema契約、platformを持つruntime evidence。
    /// - Throws: Bundle version欠落またはversion不変条件違反。
    func evidence() async throws -> ConnectionSessionAcquisitionRuntimeEvidence {
        guard let marketingVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              let buildVersion = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String else {
            throw BundleConnectionSessionAcquisitionEvidenceError.versionUnavailable
        }
        return ConnectionSessionAcquisitionRuntimeEvidence(
            applicationVersion: try AcquisitionApplicationVersion(
                marketingVersion: marketingVersion,
                buildVersion: buildVersion
            ),
            schemaContractVersion: schemaContractVersion,
            acquisitionPlatform: acquisitionPlatform
        )
    }
}

/// Bundle由来の取得runtime evidenceを生成できない理由です。
nonisolated enum BundleConnectionSessionAcquisitionEvidenceError: Error, Equatable, Sendable {
    /// marketing versionまたはbuild versionが存在しません。
    case versionUnavailable
}
