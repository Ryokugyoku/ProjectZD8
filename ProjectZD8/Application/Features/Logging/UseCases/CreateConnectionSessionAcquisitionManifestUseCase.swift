import Foundation

/// 1件のPIDについてmanifestへ固定する能力と収集選択のApplication入力です。
nonisolated struct ConnectionSessionAcquisitionPIDCapabilityInput: Equatable, Sendable {
    /// 能力証拠を結び付けるService/PIDです。
    let request: OBDPIDRequest
    /// 明示証拠に基づく対応状態です。
    let support: AcquisitionPIDCapabilitySupport
    /// 対応状態とは独立した今回の収集選択です。
    let isCollectionEnabled: Bool

    /// PID能力と収集選択を明示入力として固定します。
    ///
    /// 責務: 1件のService/PIDについて対応状態と収集選択を別軸で保持します。
    /// - Parameters:
    ///   - request: 能力証拠を結び付けるService/PID。
    ///   - support: `supported`、`unsupported`、`indeterminate`の明示状態。
    ///   - isCollectionEnabled: 今回の収集選択。
    init(
        request: OBDPIDRequest,
        support: AcquisitionPIDCapabilitySupport,
        isCollectionEnabled: Bool
    ) {
        self.request = request
        self.support = support
        self.isCollectionEnabled = isCollectionEnabled
    }
}

/// session取得manifestを作成する決定済みApplication入力です。
nonisolated struct CreateConnectionSessionAcquisitionManifestInput: Sendable {
    /// manifestを所有するsession識別子です。
    let sessionID: ConnectionSessionID
    /// 取得workflowが割り当てたpolling世代です。
    let generation: UInt
    /// manifest構造の明示versionです。
    let manifestVersion: Int
    /// polling方針の明示versionです。
    let pollingPolicyVersion: Int
    /// model入力変換契約の明示versionです。
    let modelInputManifestVersion: Int
    /// formula文字列の比較規則を示す明示versionです。
    let formulaCanonicalizationVersion: Int
    /// 取得開始時点のPID定義一覧です。
    let pidDefinitions: [OBDPIDDefinition]
    /// 取得開始時点のPID能力と収集選択一覧です。
    let pidCapabilities: [ConnectionSessionAcquisitionPIDCapabilityInput]
    /// policyが確定した要求順のService/PID一覧です。
    let orderedRequestedPIDs: [OBDPIDRequest]

    /// manifest作成へ渡す確定済み入力を保持します。
    ///
    /// 責務: session、世代、version、PID定義、能力、要求順を推測のない作成要求へまとめます。
    /// - Parameters:
    ///   - sessionID: manifestを所有するsession識別子。
    ///   - generation: 取得workflowが割り当てたpolling世代。
    ///   - manifestVersion: manifest構造の明示version。
    ///   - pollingPolicyVersion: polling方針の明示version。
    ///   - modelInputManifestVersion: model入力変換契約の明示version。
    ///   - formulaCanonicalizationVersion: formula比較規則の明示version。
    ///   - pidDefinitions: 取得開始時点のPID定義一覧。
    ///   - pidCapabilities: 取得開始時点のPID能力と収集選択一覧。
    ///   - orderedRequestedPIDs: policyが確定した要求順のService/PID一覧。
    init(
        sessionID: ConnectionSessionID,
        generation: UInt,
        manifestVersion: Int,
        pollingPolicyVersion: Int,
        modelInputManifestVersion: Int,
        formulaCanonicalizationVersion: Int,
        pidDefinitions: [OBDPIDDefinition],
        pidCapabilities: [ConnectionSessionAcquisitionPIDCapabilityInput],
        orderedRequestedPIDs: [OBDPIDRequest]
    ) {
        self.sessionID = sessionID
        self.generation = generation
        self.manifestVersion = manifestVersion
        self.pollingPolicyVersion = pollingPolicyVersion
        self.modelInputManifestVersion = modelInputManifestVersion
        self.formulaCanonicalizationVersion = formulaCanonicalizationVersion
        self.pidDefinitions = pidDefinitions
        self.pidCapabilities = pidCapabilities
        self.orderedRequestedPIDs = orderedRequestedPIDs
    }
}

/// manifest保存と開始境界保存が完了したRaw取得許可です。
nonisolated struct ConnectionSessionRawAcquisitionPermission: Equatable, Sendable {
    /// 許可対象のsession識別子です。
    let sessionID: ConnectionSessionID
    /// 許可対象のpolling世代です。
    let generation: UInt
    /// 保存済みのimmutable manifestです。
    let manifest: ConnectionSessionAcquisitionManifest

    /// 保存完了済みのRaw取得許可を生成します。
    ///
    /// 責務: 保存済みmanifestを同じsessionとpolling世代のRaw開始許可へ結び付けます。
    /// - Parameters:
    ///   - sessionID: 許可対象のsession識別子。
    ///   - generation: 許可対象のpolling世代。
    ///   - manifest: 保存済みのimmutable manifest。
    init(
        sessionID: ConnectionSessionID,
        generation: UInt,
        manifest: ConnectionSessionAcquisitionManifest
    ) {
        self.sessionID = sessionID
        self.generation = generation
        self.manifest = manifest
    }
}

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

/// 確定済み取得入力からsessionの取得開始証拠を原子的に保存します。
actor CreateConnectionSessionAcquisitionManifestUseCase {
    /// manifestとRaw開始境界の原子的な保存先です。
    private let acquisitionRepository: any ConnectionSessionAcquisitionRepository
    /// app/build、schema契約、platformのauthorityです。
    private let evidencePort: any ConnectionSessionAcquisitionEvidencePort
    /// Raw取得開始許可直前の時刻を供給します。
    private let now: @Sendable () -> Date
    /// 現在の取得workflowが有効としたpolling世代です。
    private var activeGeneration: UInt?
    /// 同一sessionと世代のretryで再利用するRaw開始境界です。
    private var retainedStartBoundary: RetainedConnectionSessionAcquisitionStartBoundary?

    /// 原子repository、runtime evidence、clockを固定します。
    ///
    /// 責務: manifest作成workflowの原子的な永続化境界とruntime authorityを注入します。
    /// - Parameters:
    ///   - acquisitionRepository: manifestとRaw開始境界の原子的な保存先。
    ///   - evidencePort: app/build、schema契約、platformのauthority。
    ///   - now: Raw取得開始許可直前の時刻供給元。
    init(
        acquisitionRepository: any ConnectionSessionAcquisitionRepository,
        evidencePort: any ConnectionSessionAcquisitionEvidencePort,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.acquisitionRepository = acquisitionRepository
        self.evidencePort = evidencePort
        self.now = now
        activeGeneration = nil
        retainedStartBoundary = nil
    }

    /// 新しいpolling世代だけをmanifest作成対象として有効化します。
    ///
    /// 責務: 後続のmanifest作成結果を照合する現在世代を置き換えます。
    /// - Parameter generation: 取得workflowが開始する新しいpolling世代。
    func activate(generation: UInt) {
        if activeGeneration != generation {
            retainedStartBoundary = nil
        }
        activeGeneration = generation
    }

    /// 指定polling世代の未完了manifest作成を無効化します。
    ///
    /// 責務: 現在世代と一致する取得開始だけをcancel済み状態へ遷移させます。
    /// - Parameter generation: cancelするpolling世代。
    func cancel(generation: UInt) {
        guard activeGeneration == generation else { return }
        activeGeneration = nil
        retainedStartBoundary = nil
    }

    /// 確定済み入力をmanifestへ変換し、開始証拠の原子保存後だけRaw開始を許可します。
    ///
    /// 責務: 現在世代のmanifestと開始境界を部分成功なしで保存してRaw開始許可を返します。
    /// - Parameter input: session、世代、version、PID定義、能力、要求順を含む確定済み入力。
    /// - Returns: manifestと開始境界の保存に成功した同一session・世代のRaw開始許可。
    /// - Throws: 世代不一致、入力欠落、Domain不変条件、runtime取得、repository保存のいずれかが失敗した場合のエラー。
    func execute(
        _ input: CreateConnectionSessionAcquisitionManifestInput
    ) async throws -> ConnectionSessionRawAcquisitionPermission {
        try ensureCurrent(generation: input.generation)
        let runtimeEvidence = try await evidencePort.evidence()
        try Task.checkCancellation()
        try ensureCurrent(generation: input.generation)
        let manifest = try makeManifest(from: input, runtimeEvidence: runtimeEvidence)
        try Task.checkCancellation()
        try ensureCurrent(generation: input.generation)
        let startedAt = startBoundaryDate(
            sessionID: input.sessionID,
            generation: input.generation
        )
        do {
            try acquisitionRepository.saveStartOnce(
                manifest: manifest,
                startedAt: startedAt,
                for: input.sessionID
            )
        } catch ConnectionSessionAcquisitionRepositoryError.duplicate {
            guard try acquisitionRepository.manifest(for: input.sessionID) == manifest else {
                throw ConnectionSessionAcquisitionRepositoryError.conflict
            }
        }
        return ConnectionSessionRawAcquisitionPermission(
            sessionID: input.sessionID,
            generation: input.generation,
            manifest: manifest
        )
    }

    /// 指定世代が現在の取得workflowに属することを検証します。
    ///
    /// 責務: staleまたはcancel済み世代を永続化処理より前に拒否します。
    /// - Parameter generation: 検証するpolling世代。
    /// - Throws: 現在世代と一致しない場合は `CreateConnectionSessionAcquisitionManifestError.inactiveGeneration`。
    private func ensureCurrent(generation: UInt) throws {
        guard activeGeneration == generation else {
            throw CreateConnectionSessionAcquisitionManifestError.inactiveGeneration
        }
    }

    /// 同じsessionと世代のretryへ同一の開始境界時刻を返します。
    ///
    /// 責務: 原子保存結果が曖昧でもretryが既存開始eventを書き換えない安定入力を供給します。
    /// - Parameters:
    ///   - sessionID: 開始境界を所有するsession識別子。
    ///   - generation: 開始境界を所有するpolling世代。
    /// - Returns: 初回に採番し同じsessionと世代で再利用する開始境界時刻。
    private func startBoundaryDate(
        sessionID: ConnectionSessionID,
        generation: UInt
    ) -> Date {
        if let retainedStartBoundary,
           retainedStartBoundary.sessionID == sessionID,
           retainedStartBoundary.generation == generation {
            return retainedStartBoundary.startedAt
        }
        let startedAt = now()
        retainedStartBoundary = RetainedConnectionSessionAcquisitionStartBoundary(
            sessionID: sessionID,
            generation: generation,
            startedAt: startedAt
        )
        return startedAt
    }

    /// Application入力をDomain manifestへ変換します。
    ///
    /// 責務: runtime evidenceとPID取得入力を欠落補完なしでimmutable manifestへ変換します。
    /// - Parameters:
    ///   - input: version、PID定義、能力、要求順を含むApplication入力。
    ///   - runtimeEvidence: portが返したapp/build、schema契約、platform。
    /// - Returns: session識別情報をsemantic identityへ含めないDomain manifest。
    /// - Throws: 入力欠落またはDomain不変条件に違反した場合のエラー。
    private func makeManifest(
        from input: CreateConnectionSessionAcquisitionManifestInput,
        runtimeEvidence: ConnectionSessionAcquisitionRuntimeEvidence
    ) throws -> ConnectionSessionAcquisitionManifest {
        let capabilityRequests = input.pidCapabilities.map(\.request)
        guard Set(capabilityRequests).count == capabilityRequests.count else {
            throw CreateConnectionSessionAcquisitionManifestError.duplicateCapabilityEvidence
        }
        let definitionRequests = input.pidDefinitions.map {
            OBDPIDRequest(service: $0.service, pid: $0.pid)
        }
        let capabilityByRequest = Dictionary(
            uniqueKeysWithValues: input.pidCapabilities.map { ($0.request, $0) }
        )
        guard Set(definitionRequests).isSubset(of: Set(capabilityRequests)) else {
            throw CreateConnectionSessionAcquisitionManifestError.capabilityEvidenceMissing
        }
        guard Set(capabilityRequests).isSubset(of: Set(definitionRequests)) else {
            throw CreateConnectionSessionAcquisitionManifestError.pidDefinitionEvidenceMissing
        }
        let snapshots = try input.pidDefinitions.map { definition in
            let request = OBDPIDRequest(service: definition.service, pid: definition.pid)
            guard let capability = capabilityByRequest[request] else {
                throw CreateConnectionSessionAcquisitionManifestError.capabilityEvidenceMissing
            }
            return try makeSnapshot(
                definition: definition,
                capability: capability,
                canonicalizationVersion: input.formulaCanonicalizationVersion
            )
        }
        return try ConnectionSessionAcquisitionManifest(
            manifestVersion: input.manifestVersion,
            applicationVersion: runtimeEvidence.applicationVersion,
            schemaContractVersion: runtimeEvidence.schemaContractVersion,
            pollingPolicyVersion: input.pollingPolicyVersion,
            orderedRequestedPIDs: OrderedAcquisitionPIDSet(requests: input.orderedRequestedPIDs),
            pidDefinitions: snapshots,
            acquisitionPlatform: runtimeEvidence.acquisitionPlatform,
            modelInputManifestVersion: input.modelInputManifestVersion
        )
    }

    /// 既存PID定義と明示capabilityをDomain snapshotへ変換します。
    ///
    /// 責務: 1件のPIDについてrevision、bytes、formula identity、unit、range、能力、選択を欠落なしで固定します。
    /// - Parameters:
    ///   - definition: 取得開始時点のPID定義。
    ///   - capability: 同じService/PIDの明示能力と収集選択。
    ///   - canonicalizationVersion: formula比較規則の明示version。
    /// - Returns: 完全な取得時PID definition snapshot。
    /// - Throws: 必須definition fieldまたはvalidity rangeが不完全な場合のエラー。
    private func makeSnapshot(
        definition: OBDPIDDefinition,
        capability: ConnectionSessionAcquisitionPIDCapabilityInput,
        canonicalizationVersion: Int
    ) throws -> AcquisitionPIDDefinitionSnapshot {
        guard definition.revision > 0,
              let requiredByteCount = definition.requiredByteCount,
              requiredByteCount > 0,
              let formula = definition.formula,
              !formula.isEmpty,
              !definition.unit.isEmpty else {
            throw CreateConnectionSessionAcquisitionManifestError.incompletePIDDefinition
        }
        let validityRange: AcquisitionPIDValidityRange
        switch (definition.minimumValue, definition.maximumValue) {
        case let (.some(minimum), .some(maximum)):
            validityRange = try .inclusive(minimum: minimum, maximum: maximum)
        case (.none, .none):
            validityRange = .notDeclared
        default:
            throw CreateConnectionSessionAcquisitionManifestError.incompleteValidityRange
        }
        return try AcquisitionPIDDefinitionSnapshot(
            request: capability.request,
            capabilitySupport: capability.support,
            isCollectionEnabled: capability.isCollectionEnabled,
            definitionRevision: definition.revision,
            requiredByteCount: requiredByteCount,
            definitionIdentity: AcquisitionPIDDefinitionIdentity(
                canonicalizationVersion: canonicalizationVersion,
                expression: formula
            ),
            unit: definition.unit,
            validityRange: validityRange
        )
    }
}

/// 原子保存retryまで保持するsession単位のRaw開始境界です。
nonisolated private struct RetainedConnectionSessionAcquisitionStartBoundary {
    /// 開始境界を所有するsession識別子です。
    let sessionID: ConnectionSessionID
    /// 開始境界を所有するpolling世代です。
    let generation: UInt
    /// 最初の保存試行で採番した開始境界時刻です。
    let startedAt: Date

    /// retry用の開始境界を生成します。
    ///
    /// 責務: session、世代、開始時刻を再実行可能な1件の保存入力として保持します。
    /// - Parameters:
    ///   - sessionID: 開始境界を所有するsession識別子。
    ///   - generation: 開始境界を所有するpolling世代。
    ///   - startedAt: 最初の保存試行で採番した開始境界時刻。
    init(sessionID: ConnectionSessionID, generation: UInt, startedAt: Date) {
        self.sessionID = sessionID
        self.generation = generation
        self.startedAt = startedAt
    }
}
