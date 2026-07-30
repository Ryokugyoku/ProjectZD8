/// Production取得証拠へ適用する明示的な契約version authorityです。
nonisolated struct ProductionConnectionSessionAcquisitionConfiguration: Sendable {
    /// manifest構造versionです。
    let manifestVersion: Int
    /// GRDB readerが解釈するschema契約versionです。
    let schemaContractVersion: Int
    /// polling policy契約versionです。
    let pollingPolicyVersion: Int
    /// model入力変換契約versionです。
    let modelInputManifestVersion: Int
    /// formula canonicalization契約versionです。
    let formulaCanonicalizationVersion: Int

    /// Phase 4Gで承認された最初のProduction契約です。
    static let phase4G = ProductionConnectionSessionAcquisitionConfiguration(
        manifestVersion: 1,
        schemaContractVersion: 1,
        pollingPolicyVersion: 1,
        modelInputManifestVersion: 1,
        formulaCanonicalizationVersion: 1
    )

    /// 各version authorityを固定します。
    ///
    /// 責務: 取得証拠を解釈する5種類の独立versionを1件のProduction構成へまとめます。
    /// - Parameters:
    ///   - manifestVersion: manifest構造version。
    ///   - schemaContractVersion: schema契約version。
    ///   - pollingPolicyVersion: polling policy契約version。
    ///   - modelInputManifestVersion: model入力変換契約version。
    ///   - formulaCanonicalizationVersion: formula canonicalization契約version。
    init(
        manifestVersion: Int,
        schemaContractVersion: Int,
        pollingPolicyVersion: Int,
        modelInputManifestVersion: Int,
        formulaCanonicalizationVersion: Int
    ) {
        self.manifestVersion = manifestVersion
        self.schemaContractVersion = schemaContractVersion
        self.pollingPolicyVersion = pollingPolicyVersion
        self.modelInputManifestVersion = modelInputManifestVersion
        self.formulaCanonicalizationVersion = formulaCanonicalizationVersion
    }
}
