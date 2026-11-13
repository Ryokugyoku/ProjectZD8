/// manifest作成時点の取得runtime evidenceです。
nonisolated struct ConnectionSessionAcquisitionRuntimeEvidence: Equatable, Sendable {
    /// 取得を生成するアプリとbuildのversionです。
    let applicationVersion: AcquisitionApplicationVersion
    /// 永続化readerが解釈するschema契約versionです。
    let schemaContractVersion: Int
    /// 端末名を含まない取得platformです。
    let acquisitionPlatform: ConnectionSessionAcquisitionPlatform

    /// runtime authorityから得たmanifest evidenceを固定します。
    ///
    /// 責務: app/build、schema契約、platformを1回のmanifest作成入力へまとめます。
    /// - Parameters:
    ///   - applicationVersion: 取得を生成するアプリとbuildのversion。
    ///   - schemaContractVersion: 永続化readerが解釈するschema契約version。
    ///   - acquisitionPlatform: 端末名を含まない取得platform。
    init(
        applicationVersion: AcquisitionApplicationVersion,
        schemaContractVersion: Int,
        acquisitionPlatform: ConnectionSessionAcquisitionPlatform
    ) {
        self.applicationVersion = applicationVersion
        self.schemaContractVersion = schemaContractVersion
        self.acquisitionPlatform = acquisitionPlatform
    }
}

/// manifest作成に必要なruntime evidenceを取得する能力です。
nonisolated protocol ConnectionSessionAcquisitionEvidencePort: Sendable {
    /// 現在実行中のapp/build、schema契約、platformを読み取ります。
    ///
    /// 責務: Production定数をApplicationで推測せずmanifest用runtime evidenceとして返します。
    /// - Returns: authorityから読み取った取得runtime evidence。
    /// - Throws: evidence authorityを利用できない場合の実装固有エラー。
    func evidence() async throws -> ConnectionSessionAcquisitionRuntimeEvidence
}
