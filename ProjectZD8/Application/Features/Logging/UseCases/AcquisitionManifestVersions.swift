/// manifestへ記録する取得契約のversion一式です。
nonisolated struct AcquisitionManifestVersions: Equatable, Sendable {
    /// manifest構造versionです。
    let manifestVersion: Int
    /// polling policy契約versionです。
    let pollingPolicyVersion: Int
    /// model入力変換契約versionです。
    let modelInputManifestVersion: Int
    /// formula canonicalization契約versionです。
    let formulaCanonicalizationVersion: Int

    /// 各version authorityを固定します。
    ///
    /// 責務: manifest作成に使う4種類のversionを1件にまとめます。
    /// - Parameters:
    ///   - manifestVersion: manifest構造version。
    ///   - pollingPolicyVersion: polling policy契約version。
    ///   - modelInputManifestVersion: model入力変換契約version。
    ///   - formulaCanonicalizationVersion: formula canonicalization契約version。
    init(
        manifestVersion: Int,
        pollingPolicyVersion: Int,
        modelInputManifestVersion: Int,
        formulaCanonicalizationVersion: Int
    ) {
        self.manifestVersion = manifestVersion
        self.pollingPolicyVersion = pollingPolicyVersion
        self.modelInputManifestVersion = modelInputManifestVersion
        self.formulaCanonicalizationVersion = formulaCanonicalizationVersion
    }
}
