import XCTest
@testable import ProjectZD8

/// 取得manifestのexact、再decode承認、非互換、unknown判定を検証します。
final class AcquisitionManifestCompatibilityPolicyTests: XCTestCase {
    /// 同一の完全manifestをexact compatibleと判定します。
    ///
    /// 責務: 全契約が一致するmanifestのexact互換性を確認します。
    func testExactlyCompatible() throws {
        let manifest = try makeManifest()

        XCTAssertEqual(policy.compatibility(acquired: manifest, candidate: manifest), .exactlyCompatible)
    }

    /// PID順序の差を非互換にします。
    ///
    /// 責務: 同じPID要素でもordered setの並びが違えば非互換になることを確認します。
    func testPIDOrderDifferenceIsIncompatible() throws {
        let acquired = try makeManifest(requests: [firstRequest, secondRequest])
        let candidate = try makeManifest(requests: [secondRequest, firstRequest])

        XCTAssertEqual(
            policy.compatibility(acquired: acquired, candidate: candidate),
            .incompatible(reasons: [.orderedPIDSetMismatch])
        )
    }

    /// PID definition revision差を非互換にします。
    ///
    /// 責務: revision番号だけが異なる定義を自動互換にしないことを確認します。
    func testRevisionDifferenceIsIncompatible() throws {
        try assertDefinitionDifference(reason: .definitionRevisionMismatch, candidate: makeDefinition(revision: 2))
    }

    /// 必要byte数差を非互換にします。
    ///
    /// 責務: 同じrevisionでも必要byte数の差を検出することを確認します。
    func testRequiredByteCountDifferenceIsIncompatible() throws {
        try assertDefinitionDifference(reason: .requiredByteCountMismatch, candidate: makeDefinition(requiredByteCount: 1))
    }

    /// formula identity差を非互換にします。
    ///
    /// 責務: 同じrevisionでも完全な式identityの差を検出することを確認します。
    func testDefinitionIdentityDifferenceIsIncompatible() throws {
        let identity = try AcquisitionPIDDefinitionIdentity(canonicalizationVersion: 1, expression: "A * 256 + B")
        try assertDefinitionDifference(reason: .definitionIdentityMismatch, candidate: makeDefinition(identity: identity))
    }

    /// 単位差を非互換にします。
    ///
    /// 責務: 同じrevisionでもsemantic unitの差を検出することを確認します。
    func testUnitDifferenceIsIncompatible() throws {
        try assertDefinitionDifference(reason: .unitMismatch, candidate: makeDefinition(unit: "rps"))
    }

    /// 有効範囲差を非互換にします。
    ///
    /// 責務: 同じrevisionでもinclusive validity rangeの差を検出することを確認します。
    func testValidityRangeDifferenceIsIncompatible() throws {
        let range = try AcquisitionPIDValidityRange.inclusive(minimum: 0, maximum: 8_000)
        try assertDefinitionDifference(reason: .validityRangeMismatch, candidate: makeDefinition(validityRange: range))
    }

    /// manifest version差を非互換にします。
    ///
    /// 責務: readerが理解できるmanifest version同士の差を非互換にすることを確認します。
    func testManifestVersionDifferenceIsIncompatible() throws {
        let versionPolicy = makePolicy(manifestVersions: [1, 2])
        let result = versionPolicy.compatibility(acquired: try makeManifest(), candidate: try makeManifest(manifestVersion: 2))

        XCTAssertEqual(result, .incompatible(reasons: [.manifestVersionMismatch]))
    }

    /// schema version差を非互換にします。
    ///
    /// 責務: readerが理解できるschema contract version同士の差を非互換にすることを確認します。
    func testSchemaVersionDifferenceIsIncompatible() throws {
        let versionPolicy = makePolicy(schemaVersions: [1, 2])
        let result = versionPolicy.compatibility(acquired: try makeManifest(), candidate: try makeManifest(schemaVersion: 2))

        XCTAssertEqual(result, .incompatible(reasons: [.schemaContractVersionMismatch]))
    }

    /// polling policy version差を非互換にします。
    ///
    /// 責務: readerが理解できるpolling policy version同士の差を非互換にすることを確認します。
    func testPollingPolicyVersionDifferenceIsIncompatible() throws {
        let versionPolicy = makePolicy(pollingVersions: [1, 2])
        let result = versionPolicy.compatibility(acquired: try makeManifest(), candidate: try makeManifest(pollingVersion: 2))

        XCTAssertEqual(result, .incompatible(reasons: [.pollingPolicyVersionMismatch]))
    }

    /// model入力version差を非互換にします。
    ///
    /// 責務: readerが理解できるmodel input manifest version同士の差を非互換にすることを確認します。
    func testModelInputVersionDifferenceIsIncompatible() throws {
        let versionPolicy = makePolicy(modelVersions: [1, 2])
        let result = versionPolicy.compatibility(acquired: try makeManifest(), candidate: try makeManifest(modelVersion: 2))

        XCTAssertEqual(result, .incompatible(reasons: [.modelInputManifestVersionMismatch]))
    }

    /// 取得時revision欠落をunknownにします。
    ///
    /// 責務: legacy欠落値を現在定義から補完せずunknownへ止めることを確認します。
    func testLegacyDefinitionMetadataIsUnknown() throws {
        let legacy = try makeManifest(definitions: [makeDefinition(revision: nil), makeDefinition(request: secondRequest)])

        XCTAssertEqual(
            policy.compatibility(acquired: legacy, candidate: try makeManifest()),
            .unknown(reasons: [.acquisitionDefinitionEvidenceMissing])
        )
    }

    /// 取得manifestがないlegacy sessionをunknownにします。
    ///
    /// 責務: 現行legacy session相当のmanifest欠落を自動互換へ遷移させないことを確認します。
    func testMissingAcquisitionManifestIsUnknown() throws {
        XCTAssertEqual(
            policy.compatibility(acquired: nil, candidate: try makeManifest()),
            .unknown(reasons: [.manifestMissing])
        )
    }

    /// snapshot一覧にないPIDをunsupportedへ変換しません。
    ///
    /// 責務: PID definition snapshotの欠落を能力非対応ではなく証拠不足のunknownにすることを確認します。
    func testMissingPIDSnapshotIsUnknownRatherThanUnsupported() throws {
        let acquired = try makeManifest()
        let extraRequest = OBDPIDRequest(service: 1, pid: 14)
        let candidate = try makeManifest(
            definitions: [
                makeDefinition(),
                makeDefinition(request: secondRequest),
                makeDefinition(request: extraRequest)
            ]
        )

        XCTAssertEqual(
            policy.compatibility(acquired: acquired, candidate: candidate),
            .unknown(reasons: [.acquisitionDefinitionEvidenceMissing])
        )
    }

    /// reader未対応versionをunknownにします。
    ///
    /// 責務: 未知versionをcompatibleまたは単なるversion差へ既定化しないことを確認します。
    func testUnknownVersionIsUnknown() throws {
        let result = policy.compatibility(acquired: try makeManifest(), candidate: try makeManifest(manifestVersion: 99))

        XCTAssertEqual(result, .unknown(reasons: [.unknownManifestVersion]))
    }

    /// 明示承認なしのrevision差をapprovedへ昇格しません。
    ///
    /// 責務: 再decode承認の既定値が拒否側であることを確認します。
    func testRedecodeRequiresExplicitApproval() throws {
        let acquired = try makeManifest()
        let candidateDefinition = try makeDefinition(revision: 2)
        let candidate = try makeManifest(definitions: [candidateDefinition, makeDefinition(request: secondRequest)])

        XCTAssertEqual(
            policy.compatibility(acquired: acquired, candidate: candidate),
            .incompatible(reasons: [.definitionRevisionMismatch])
        )
    }

    /// 明示承認済み再decodeでも元manifestを変更しません。
    ///
    /// 責務: approved re-decode判定が取得時immutable evidenceを保持することを確認します。
    func testApprovedRedecodeDoesNotMutateAcquiredManifest() throws {
        let acquiredDefinition = try makeDefinition()
        let candidateDefinition = try makeDefinition(revision: 2)
        let acquired = try makeManifest(definitions: [acquiredDefinition, makeDefinition(request: secondRequest)])
        let original = acquired
        let candidate = try makeManifest(definitions: [candidateDefinition, makeDefinition(request: secondRequest)])
        let approval = ApprovedAcquisitionPIDRedecode(
            acquiredDefinition: acquiredDefinition,
            approvedDefinition: candidateDefinition
        )

        XCTAssertEqual(
            policy.compatibility(acquired: acquired, candidate: candidate, approvals: [approval]),
            .approvedRedecodeCompatible
        )
        XCTAssertEqual(acquired, original)
    }

    /// 比較に使う既知version policyです。
    private var policy: AcquisitionManifestCompatibilityPolicy { makePolicy() }
    /// 最初のsynthetic Service/PIDです。
    private var firstRequest: OBDPIDRequest { OBDPIDRequest(service: 1, pid: 12) }
    /// 2番目のsynthetic Service/PIDです。
    private var secondRequest: OBDPIDRequest { OBDPIDRequest(service: 1, pid: 13) }

    /// 指定PID semantic差の単独reasonを検証します。
    ///
    /// 責務: 1件のPID定義差を期待する非互換reasonと照合します。
    /// - Parameters:
    ///   - reason: 期待する単独の非互換reason。
    ///   - candidate: 比較側で差し替えるPID定義。
    private func assertDefinitionDifference(
        reason: AcquisitionManifestIncompatibilityReason,
        candidate: AcquisitionPIDDefinitionSnapshot
    ) throws {
        let acquired = try makeManifest()
        let compared = try makeManifest(definitions: [candidate, makeDefinition(request: secondRequest)])

        XCTAssertEqual(policy.compatibility(acquired: acquired, candidate: compared), .incompatible(reasons: [reason]))
    }

    /// version authorityを差し替えたpolicyを生成します。
    ///
    /// 責務: 各version軸を独立検証できるcompatibility policy fixtureを返します。
    /// - Parameters:
    ///   - manifestVersions: 既知manifest version集合。
    ///   - schemaVersions: 既知schema contract version集合。
    ///   - pollingVersions: 既知polling policy version集合。
    ///   - modelVersions: 既知model input manifest version集合。
    /// - Returns: 指定versionだけを既知とするpolicy。
    private func makePolicy(
        manifestVersions: Set<Int> = [1],
        schemaVersions: Set<Int> = [1],
        pollingVersions: Set<Int> = [1],
        modelVersions: Set<Int> = [1]
    ) -> AcquisitionManifestCompatibilityPolicy {
        AcquisitionManifestCompatibilityPolicy(
            supportedVersions: SupportedAcquisitionContractVersions(
                manifestVersions: manifestVersions,
                schemaContractVersions: schemaVersions,
                pollingPolicyVersions: pollingVersions,
                modelInputManifestVersions: modelVersions
            )
        )
    }

    /// 完全または指定差分を持つmanifest fixtureを生成します。
    ///
    /// 責務: 識別情報を含まない決定的な取得manifestをpolicy testへ提供します。
    /// - Parameters:
    ///   - manifestVersion: manifest構造version。
    ///   - schemaVersion: schema契約version。
    ///   - pollingVersion: polling方針version。
    ///   - modelVersion: model入力契約version。
    ///   - requests: ordered PID集合。
    ///   - definitions: PID定義snapshot一覧。省略時はordered setと同じ2件。
    /// - Returns: policy比較用のmanifest。
    private func makeManifest(
        manifestVersion: Int? = 1,
        schemaVersion: Int? = 1,
        pollingVersion: Int? = 1,
        modelVersion: Int? = 1,
        requests: [OBDPIDRequest]? = nil,
        definitions: [AcquisitionPIDDefinitionSnapshot]? = nil
    ) throws -> ConnectionSessionAcquisitionManifest {
        let orderedRequests = requests ?? [firstRequest, secondRequest]
        let snapshots = try definitions ?? [makeDefinition(), makeDefinition(request: secondRequest)]
        return try ConnectionSessionAcquisitionManifest(
            manifestVersion: manifestVersion,
            applicationVersion: AcquisitionApplicationVersion(marketingVersion: "test-version", buildVersion: "test-build"),
            schemaContractVersion: schemaVersion,
            pollingPolicyVersion: pollingVersion,
            orderedRequestedPIDs: OrderedAcquisitionPIDSet(requests: orderedRequests),
            pidDefinitions: snapshots,
            acquisitionPlatform: .iPhone,
            modelInputManifestVersion: modelVersion
        )
    }

    /// 完全または指定差分を持つPID定義fixtureを生成します。
    ///
    /// 責務: 1件のPID semantic fieldだけを差し替えられる定義snapshotを返します。
    /// - Parameters:
    ///   - request: Service/PID。
    ///   - revision: 取得時revision。
    ///   - requiredByteCount: 必要byte数。
    ///   - identity: 完全な式identity。
    ///   - unit: semantic unit。
    ///   - validityRange: inclusive validity range。
    /// - Returns: policy比較用のPID定義snapshot。
    private func makeDefinition(
        request: OBDPIDRequest? = nil,
        revision: Int? = 1,
        requiredByteCount: Int? = 2,
        identity: AcquisitionPIDDefinitionIdentity? = nil,
        unit: String? = "rpm",
        validityRange: AcquisitionPIDValidityRange? = nil
    ) throws -> AcquisitionPIDDefinitionSnapshot {
        try AcquisitionPIDDefinitionSnapshot(
            request: request ?? firstRequest,
            capabilitySupport: .supported,
            isCollectionEnabled: true,
            definitionRevision: revision,
            requiredByteCount: requiredByteCount,
            definitionIdentity: identity ?? AcquisitionPIDDefinitionIdentity(
                canonicalizationVersion: 1,
                expression: "(A * 256 + B) / 4"
            ),
            unit: unit,
            validityRange: try validityRange ?? AcquisitionPIDValidityRange.inclusive(minimum: 0, maximum: 16_383.75)
        )
    }
}
