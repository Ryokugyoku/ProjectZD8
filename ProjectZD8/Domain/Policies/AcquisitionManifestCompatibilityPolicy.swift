/// 互換性判定でreaderが理解できる契約version集合です。
nonisolated struct SupportedAcquisitionContractVersions: Equatable, Sendable {
    /// 対応するmanifest構造versionです。
    let manifestVersions: Set<Int>
    /// 対応する保存schema契約versionです。
    let schemaContractVersions: Set<Int>
    /// 対応するpolling方針versionです。
    let pollingPolicyVersions: Set<Int>
    /// 対応するmodel入力契約versionです。
    let modelInputManifestVersions: Set<Int>

    /// readerが明示対応するversion集合を生成します。
    ///
    /// 責務: 互換性policyが既知として扱える4種類の契約versionを固定します。
    /// - Parameters:
    ///   - manifestVersions: 対応するmanifest構造version。
    ///   - schemaContractVersions: 対応する保存schema契約version。
    ///   - pollingPolicyVersions: 対応するpolling方針version。
    ///   - modelInputManifestVersions: 対応するmodel入力契約version。
    init(
        manifestVersions: Set<Int>,
        schemaContractVersions: Set<Int>,
        pollingPolicyVersions: Set<Int>,
        modelInputManifestVersions: Set<Int>
    ) {
        self.manifestVersions = manifestVersions
        self.schemaContractVersions = schemaContractVersions
        self.pollingPolicyVersions = pollingPolicyVersions
        self.modelInputManifestVersions = modelInputManifestVersions
    }
}

/// 人間が明示承認した取得時定義から別定義への再decode契約です。
nonisolated struct ApprovedAcquisitionPIDRedecode: Equatable, Sendable {
    /// 変更されない取得時PID snapshotです。
    let acquiredDefinition: AcquisitionPIDDefinitionSnapshot
    /// 再decodeで使用を承認されたPID snapshotです。
    let approvedDefinition: AcquisitionPIDDefinitionSnapshot

    /// 取得時定義と承認済み再decode定義の対を生成します。
    ///
    /// 責務: 1件のPIDについて方向付きの再decode承認範囲を完全な値の対へ固定します。
    /// - Parameters:
    ///   - acquiredDefinition: 変更しない取得時PID snapshot。
    ///   - approvedDefinition: 再decodeで使用を承認されたPID snapshot。
    init(acquiredDefinition: AcquisitionPIDDefinitionSnapshot, approvedDefinition: AcquisitionPIDDefinitionSnapshot) {
        self.acquiredDefinition = acquiredDefinition
        self.approvedDefinition = approvedDefinition
    }
}

/// manifestが互換ではない機械判定理由です。
nonisolated enum AcquisitionManifestIncompatibilityReason: String, Equatable, Hashable, Sendable {
    /// manifest構造versionが異なります。
    case manifestVersionMismatch
    /// アプリまたはbuild versionが異なります。
    case applicationVersionMismatch
    /// 保存schema契約versionが異なります。
    case schemaContractVersionMismatch
    /// polling方針versionが異なります。
    case pollingPolicyVersionMismatch
    /// model入力契約versionが異なります。
    case modelInputManifestVersionMismatch
    /// 取得platformが異なります。
    case acquisitionPlatformMismatch
    /// ordered PID集合の要素または順序が異なります。
    case orderedPIDSetMismatch
    /// PID対応状態または収集選択が異なります。
    case pidCapabilityMismatch
    /// PID定義revisionが異なります。
    case definitionRevisionMismatch
    /// 必要byte数が異なります。
    case requiredByteCountMismatch
    /// 式またはcanonicalization契約が異なります。
    case definitionIdentityMismatch
    /// 単位が異なります。
    case unitMismatch
    /// 有効範囲が異なります。
    case validityRangeMismatch
}

/// manifest互換性を証拠不足で決められない機械判定理由です。
nonisolated enum AcquisitionManifestUnknownReason: String, Equatable, Hashable, Sendable {
    /// 取得manifest自体がありません。
    case manifestMissing
    /// manifest構造versionが欠落しています。
    case legacyManifestVersionMissing
    /// アプリまたはbuild versionが欠落しています。
    case legacyApplicationVersionMissing
    /// 保存schema契約versionが欠落しています。
    case legacySchemaContractVersionMissing
    /// polling方針versionが欠落しています。
    case legacyPollingPolicyVersionMissing
    /// ordered PID集合が欠落しています。
    case legacyRequestedPIDSetMissing
    /// 取得platformが欠落しています。
    case legacyAcquisitionPlatformMissing
    /// model入力契約versionが欠落しています。
    case legacyModelInputManifestVersionMissing
    /// PID能力または収集選択の証拠が欠落しています。
    case legacyCapabilityEvidenceMissing
    /// 取得時PID定義のsemantic metadataが欠落しています。
    case acquisitionDefinitionEvidenceMissing
    /// manifest構造versionをreaderが理解できません。
    case unknownManifestVersion
    /// 保存schema契約versionをreaderが理解できません。
    case unknownSchemaContractVersion
    /// polling方針versionをreaderが理解できません。
    case unknownPollingPolicyVersion
    /// model入力契約versionをreaderが理解できません。
    case unknownModelInputManifestVersion
}

/// 2件の取得manifestに対する排他的互換性結果です。
nonisolated enum AcquisitionManifestCompatibility: Equatable, Sendable {
    /// 全ての比較対象契約が一致します。
    case exactlyCompatible
    /// 差のある全PID定義が明示承認済み再decode契約に一致します。
    case approvedRedecodeCompatible
    /// 証拠は揃っていますが互換でない理由があります。
    case incompatible(reasons: [AcquisitionManifestIncompatibilityReason])
    /// legacy欠落、未知version、または証拠不足により判定できません。
    case unknown(reasons: [AcquisitionManifestUnknownReason])
}

/// 取得manifest同士を明示versionとsemantic evidenceで比較します。
nonisolated struct AcquisitionManifestCompatibilityPolicy: Sendable {
    /// readerが明示対応するversion集合です。
    private let supportedVersions: SupportedAcquisitionContractVersions

    /// 対応version集合を注入してpolicyを生成します。
    ///
    /// 責務: manifest互換性判定で既知とする契約versionのauthorityを固定します。
    /// - Parameter supportedVersions: readerが明示対応する4種類のversion集合。
    init(supportedVersions: SupportedAcquisitionContractVersions) {
        self.supportedVersions = supportedVersions
    }

    /// 取得時manifestと比較対象manifestの互換性を判定します。
    ///
    /// 責務: 欠落、未知version、完全一致、明示承認済み再decode、非互換を既定化せず排他的に返します。
    /// - Parameters:
    ///   - acquired: 変更してはならない取得時manifest。存在しないlegacy sessionは `nil`。
    ///   - candidate: 比較するreaderまたは再decode側のmanifest。存在しない場合は `nil`。
    ///   - approvals: 方向付きの明示承認済みPID再decode契約。
    /// - Returns: 識別情報を含まないreasonを伴う排他的互換性結果。
    func compatibility(
        acquired: ConnectionSessionAcquisitionManifest?,
        candidate: ConnectionSessionAcquisitionManifest?,
        approvals: [ApprovedAcquisitionPIDRedecode] = []
    ) -> AcquisitionManifestCompatibility {
        guard let acquired, let candidate else {
            return .unknown(reasons: [.manifestMissing])
        }

        let unknownReasons = unknownReasons(in: [acquired, candidate])
        guard unknownReasons.isEmpty else {
            return .unknown(reasons: unknownReasons)
        }

        var incompatibilities = manifestIncompatibilities(acquired: acquired, candidate: candidate)
        guard incompatibilities.isEmpty else {
            return .incompatible(reasons: incompatibilities)
        }

        let acquiredDefinitions = Dictionary(uniqueKeysWithValues: acquired.pidDefinitions.map { ($0.request, $0) })
        let candidateDefinitions = Dictionary(uniqueKeysWithValues: candidate.pidDefinitions.map { ($0.request, $0) })
        guard Set(acquiredDefinitions.keys) == Set(candidateDefinitions.keys) else {
            return .unknown(reasons: [.acquisitionDefinitionEvidenceMissing])
        }
        var requiresApprovedRedecode = false

        for request in acquired.pidDefinitions.map(\.request) {
            guard let acquiredDefinition = acquiredDefinitions[request],
                  let candidateDefinition = candidateDefinitions[request] else {
                return .unknown(reasons: [.acquisitionDefinitionEvidenceMissing])
            }
            if acquiredDefinition.capabilitySupport != candidateDefinition.capabilitySupport
                || acquiredDefinition.isCollectionEnabled != candidateDefinition.isCollectionEnabled {
                incompatibilities.append(.pidCapabilityMismatch)
            }

            let semanticReasons = definitionIncompatibilities(acquired: acquiredDefinition, candidate: candidateDefinition)
            guard semanticReasons.isEmpty else {
                if approvals.contains(where: {
                    $0.acquiredDefinition == acquiredDefinition && $0.approvedDefinition == candidateDefinition
                }) {
                    requiresApprovedRedecode = true
                } else {
                    incompatibilities.append(contentsOf: semanticReasons)
                }
                continue
            }
        }

        let reasons = unique(incompatibilities)
        if !reasons.isEmpty {
            return .incompatible(reasons: reasons)
        }
        return requiresApprovedRedecode ? .approvedRedecodeCompatible : .exactlyCompatible
    }

    /// legacy欠落とreader未対応versionを列挙します。
    ///
    /// 責務: 互換性比較より前に判定をunknownへ止める証拠不足を重複なく抽出します。
    /// - Parameter manifests: 取得側と比較側のmanifest。
    /// - Returns: 識別情報を含まないunknown reason一覧。
    private func unknownReasons(in manifests: [ConnectionSessionAcquisitionManifest]) -> [AcquisitionManifestUnknownReason] {
        var reasons: [AcquisitionManifestUnknownReason] = []
        for manifest in manifests {
            if manifest.manifestVersion == nil { reasons.append(.legacyManifestVersionMissing) }
            if manifest.applicationVersion == nil { reasons.append(.legacyApplicationVersionMissing) }
            if manifest.schemaContractVersion == nil { reasons.append(.legacySchemaContractVersionMissing) }
            if manifest.pollingPolicyVersion == nil { reasons.append(.legacyPollingPolicyVersionMissing) }
            if manifest.orderedRequestedPIDs == nil { reasons.append(.legacyRequestedPIDSetMissing) }
            if manifest.acquisitionPlatform == nil { reasons.append(.legacyAcquisitionPlatformMissing) }
            if manifest.modelInputManifestVersion == nil { reasons.append(.legacyModelInputManifestVersionMissing) }
            if manifest.pidDefinitions.contains(where: { $0.capabilitySupport == nil || $0.isCollectionEnabled == nil }) {
                reasons.append(.legacyCapabilityEvidenceMissing)
            }
            if manifest.pidDefinitions.contains(where: {
                $0.definitionRevision == nil || $0.requiredByteCount == nil || $0.definitionIdentity == nil
                    || $0.unit == nil || $0.validityRange == nil
            }) {
                reasons.append(.acquisitionDefinitionEvidenceMissing)
            }
            if let version = manifest.manifestVersion, !supportedVersions.manifestVersions.contains(version) {
                reasons.append(.unknownManifestVersion)
            }
            if let version = manifest.schemaContractVersion, !supportedVersions.schemaContractVersions.contains(version) {
                reasons.append(.unknownSchemaContractVersion)
            }
            if let version = manifest.pollingPolicyVersion, !supportedVersions.pollingPolicyVersions.contains(version) {
                reasons.append(.unknownPollingPolicyVersion)
            }
            if let version = manifest.modelInputManifestVersion,
               !supportedVersions.modelInputManifestVersions.contains(version) {
                reasons.append(.unknownModelInputManifestVersion)
            }
        }
        return unique(reasons)
    }

    /// session単位の既知metadata差を列挙します。
    ///
    /// 責務: PID定義以外のmanifest契約差を機械判定reasonへ変換します。
    /// - Parameters:
    ///   - acquired: 取得時manifest。
    ///   - candidate: 比較対象manifest。
    /// - Returns: session単位の非互換reason一覧。
    private func manifestIncompatibilities(
        acquired: ConnectionSessionAcquisitionManifest,
        candidate: ConnectionSessionAcquisitionManifest
    ) -> [AcquisitionManifestIncompatibilityReason] {
        var reasons: [AcquisitionManifestIncompatibilityReason] = []
        if acquired.manifestVersion != candidate.manifestVersion { reasons.append(.manifestVersionMismatch) }
        if acquired.applicationVersion != candidate.applicationVersion { reasons.append(.applicationVersionMismatch) }
        if acquired.schemaContractVersion != candidate.schemaContractVersion { reasons.append(.schemaContractVersionMismatch) }
        if acquired.pollingPolicyVersion != candidate.pollingPolicyVersion { reasons.append(.pollingPolicyVersionMismatch) }
        if acquired.modelInputManifestVersion != candidate.modelInputManifestVersion {
            reasons.append(.modelInputManifestVersionMismatch)
        }
        if acquired.acquisitionPlatform != candidate.acquisitionPlatform { reasons.append(.acquisitionPlatformMismatch) }
        if acquired.orderedRequestedPIDs != candidate.orderedRequestedPIDs { reasons.append(.orderedPIDSetMismatch) }
        return reasons
    }

    /// 1件のPID定義のsemantic差を列挙します。
    ///
    /// 責務: revisionだけに依存せずbyte数、式identity、単位、有効範囲の差を個別reasonへ変換します。
    /// - Parameters:
    ///   - acquired: 取得時PID定義snapshot。
    ///   - candidate: 比較対象PID定義snapshot。
    /// - Returns: PID定義の非互換reason一覧。
    private func definitionIncompatibilities(
        acquired: AcquisitionPIDDefinitionSnapshot,
        candidate: AcquisitionPIDDefinitionSnapshot
    ) -> [AcquisitionManifestIncompatibilityReason] {
        var reasons: [AcquisitionManifestIncompatibilityReason] = []
        if acquired.definitionRevision != candidate.definitionRevision { reasons.append(.definitionRevisionMismatch) }
        if acquired.requiredByteCount != candidate.requiredByteCount { reasons.append(.requiredByteCountMismatch) }
        if acquired.definitionIdentity != candidate.definitionIdentity { reasons.append(.definitionIdentityMismatch) }
        if acquired.unit != candidate.unit { reasons.append(.unitMismatch) }
        if acquired.validityRange != candidate.validityRange { reasons.append(.validityRangeMismatch) }
        return reasons
    }

    /// reasonの最初の出現順を保持して重複を除きます。
    ///
    /// 責務: 同じ機械判定reasonを結果へ一度だけ保持します。
    /// - Parameter values: 重複を含み得るreason一覧。
    /// - Returns: 最初の出現順を保持したreason一覧。
    private func unique<T: Hashable>(_ values: [T]) -> [T] {
        var seen: Set<T> = []
        return values.filter { seen.insert($0).inserted }
    }
}
