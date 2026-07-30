import XCTest
@testable import ProjectZD8

/// session取得manifestの生成時不変条件を検証します。
final class ConnectionSessionAcquisitionManifestTests: XCTestCase {
    /// manifestのstored semantic fieldを取得証拠だけに制限します。
    ///
    /// 責務: VIN、account、VehicleID、端末名、adapter identity、Raw payload用fieldがmanifestに存在しないことを確認します。
    func testSemanticIdentityExcludesOperationalAndPersonalIdentifiers() throws {
        let request = OBDPIDRequest(service: 1, pid: 12)
        let definition = try AcquisitionPIDDefinitionSnapshot(
            request: request,
            capabilitySupport: .indeterminate,
            isCollectionEnabled: false,
            definitionRevision: 1,
            requiredByteCount: 2,
            definitionIdentity: AcquisitionPIDDefinitionIdentity(
                canonicalizationVersion: 1,
                expression: "(A * 256 + B) / 4"
            ),
            unit: "rpm",
            validityRange: AcquisitionPIDValidityRange.inclusive(minimum: 0, maximum: 16_383.75)
        )
        let manifest = try ConnectionSessionAcquisitionManifest(
            manifestVersion: 1,
            applicationVersion: AcquisitionApplicationVersion(
                marketingVersion: "fixture-version",
                buildVersion: "fixture-build"
            ),
            schemaContractVersion: 1,
            pollingPolicyVersion: 1,
            orderedRequestedPIDs: OrderedAcquisitionPIDSet(requests: [request]),
            pidDefinitions: [definition],
            acquisitionPlatform: .macOS,
            modelInputManifestVersion: 1
        )

        XCTAssertEqual(
            Mirror(reflecting: manifest).children.compactMap(\.label),
            [
                "manifestVersion",
                "applicationVersion",
                "schemaContractVersion",
                "pollingPolicyVersion",
                "orderedRequestedPIDs",
                "pidDefinitions",
                "acquisitionPlatform",
                "modelInputManifestVersion"
            ]
        )
    }

    /// 要求PIDに対応するdefinitionがないmanifestを拒否します。
    ///
    /// 責務: 要求集合だけを保存して取得時definitionを欠落させられないことを確認します。
    func testRejectsMissingRequestedPIDDefinition() throws {
        let request = OBDPIDRequest(service: 1, pid: 12)
        XCTAssertThrowsError(
            try ConnectionSessionAcquisitionManifest(
                manifestVersion: 1,
                applicationVersion: AcquisitionApplicationVersion(
                    marketingVersion: "fixture-version",
                    buildVersion: "fixture-build"
                ),
                schemaContractVersion: 1,
                pollingPolicyVersion: 1,
                orderedRequestedPIDs: OrderedAcquisitionPIDSet(requests: [request]),
                pidDefinitions: [],
                acquisitionPlatform: .macOS,
                modelInputManifestVersion: 1
            )
        ) {
            XCTAssertEqual(
                $0 as? ConnectionSessionAcquisitionManifestError,
                .missingRequestedPIDDefinition
            )
        }
    }
}
