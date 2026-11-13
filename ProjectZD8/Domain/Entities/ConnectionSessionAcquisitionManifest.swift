/// 取得を生成したアプリのversionを表します。
nonisolated struct AcquisitionApplicationVersion: Equatable, Sendable {
    /// ユーザー向けmarketing versionです。
    let marketingVersion: String
    /// 配布buildを識別するbuild versionです。
    let buildVersion: String

    /// アプリとbuildのversionを生成します。
    ///
    /// 責務: 取得runtimeのアプリversionをmarketing値とbuild値の組へ固定します。
    /// - Parameters:
    ///   - marketingVersion: 空でないユーザー向けversion。
    ///   - buildVersion: 空でない配布build version。
    /// - Throws: いずれかが空の場合は `ConnectionSessionAcquisitionManifestError.invalidApplicationVersion`。
    init(marketingVersion: String, buildVersion: String) throws {
        guard !marketingVersion.isEmpty, !buildVersion.isEmpty else {
            throw ConnectionSessionAcquisitionManifestError.invalidApplicationVersion
        }
        self.marketingVersion = marketingVersion
        self.buildVersion = buildVersion
    }
}

/// 1件のsessionでRawを生成した取得条件の不変証拠です。
nonisolated struct ConnectionSessionAcquisitionManifest: Equatable, Sendable {
    /// manifest構造のversionです。`nil` はlegacy欠落を表します。
    let manifestVersion: Int?
    /// 取得runtimeのアプリversionです。`nil` はlegacy欠落を表します。
    let applicationVersion: AcquisitionApplicationVersion?
    /// 保存schema契約のversionです。`nil` はlegacy欠落を表します。
    let schemaContractVersion: Int?
    /// polling方針のversionです。`nil` はlegacy欠落を表します。
    let pollingPolicyVersion: Int?
    /// 順序付き要求PID集合です。`nil` はlegacy欠落を表します。
    let orderedRequestedPIDs: OrderedAcquisitionPIDSet?
    /// 取得時点のPID定義と能力選択snapshotです。
    let pidDefinitions: [AcquisitionPIDDefinitionSnapshot]
    /// 端末名を含まない取得platformです。`nil` はlegacy欠落を表します。
    let acquisitionPlatform: ConnectionSessionAcquisitionPlatform?
    /// model入力変換契約のversionです。`nil` はlegacy欠落を表します。
    let modelInputManifestVersion: Int?

    /// session単位の取得manifestを生成します。
    ///
    /// 責務: session識別情報を含めずに取得条件とPID証拠を不変manifestへ固定します。
    /// - Parameters:
    ///   - manifestVersion: 正のmanifest構造version、またはlegacy欠落を示す `nil`。
    ///   - applicationVersion: 取得runtime version、またはlegacy欠落を示す `nil`。
    ///   - schemaContractVersion: 正のschema契約version、またはlegacy欠落を示す `nil`。
    ///   - pollingPolicyVersion: 正のpolling方針version、またはlegacy欠落を示す `nil`。
    ///   - orderedRequestedPIDs: 重複のない要求PID順、またはlegacy欠落を示す `nil`。
    ///   - pidDefinitions: 取得時点のPID定義と能力選択snapshot。
    ///   - acquisitionPlatform: 端末名を含まないplatform、またはlegacy欠落を示す `nil`。
    ///   - modelInputManifestVersion: 正のmodel入力契約version、またはlegacy欠落を示す `nil`。
    /// - Throws: versionが正でない、PID snapshotが重複する、または要求PIDのsnapshotがない場合は対応する `ConnectionSessionAcquisitionManifestError`。
    init(
        manifestVersion: Int?,
        applicationVersion: AcquisitionApplicationVersion?,
        schemaContractVersion: Int?,
        pollingPolicyVersion: Int?,
        orderedRequestedPIDs: OrderedAcquisitionPIDSet?,
        pidDefinitions: [AcquisitionPIDDefinitionSnapshot],
        acquisitionPlatform: ConnectionSessionAcquisitionPlatform?,
        modelInputManifestVersion: Int?
    ) throws {
        let versions = [manifestVersion, schemaContractVersion, pollingPolicyVersion, modelInputManifestVersion].compactMap { $0 }
        guard versions.allSatisfy({ $0 > 0 }) else {
            throw ConnectionSessionAcquisitionManifestError.invalidContractVersion
        }
        let definitionRequests = pidDefinitions.map(\.request)
        guard Set(definitionRequests).count == definitionRequests.count else {
            throw ConnectionSessionAcquisitionManifestError.duplicatePIDDefinition
        }
        if let orderedRequestedPIDs {
            guard Set(orderedRequestedPIDs.requests).isSubset(of: Set(definitionRequests)) else {
                throw ConnectionSessionAcquisitionManifestError.missingRequestedPIDDefinition
            }
        }
        self.manifestVersion = manifestVersion
        self.applicationVersion = applicationVersion
        self.schemaContractVersion = schemaContractVersion
        self.pollingPolicyVersion = pollingPolicyVersion
        self.orderedRequestedPIDs = orderedRequestedPIDs
        self.pidDefinitions = pidDefinitions
        self.acquisitionPlatform = acquisitionPlatform
        self.modelInputManifestVersion = modelInputManifestVersion
    }
}

/// session取得manifestを確定できない理由です。
nonisolated enum ConnectionSessionAcquisitionManifestError: Error, Equatable, Sendable {
    /// アプリversionの一部が空です。
    case invalidApplicationVersion
    /// version契約値が正ではありません。
    case invalidContractVersion
    /// 同じService/PIDのsnapshotが複数あります。
    case duplicatePIDDefinition
    /// ordered要求集合に対応するPID snapshotがありません。
    case missingRequestedPIDDefinition
}
