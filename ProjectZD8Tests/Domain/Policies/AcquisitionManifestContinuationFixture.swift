import Foundation
@testable import ProjectZD8

/// 続行判定のテストで使う取得manifestを、1項目だけ差し替えて組み立てるテスト部品です。
///
/// 既定値はすべて決まった合成値で、実機・実車の値を含みません。
enum AcquisitionManifestContinuationFixture {
    /// 1件目のPIDです。
    static let firstRequest = OBDPIDRequest(service: 0x01, pid: 0x0C)
    /// 2件目のPIDです。
    static let secondRequest = OBDPIDRequest(service: 0x01, pid: 0x0D)
    /// ATMA判定ありのアダプター判定結果です。
    static let stnFrames = AcquisitionAdapterProbeEvidence(chipFamily: .stn, monitorProbeOutcome: .framesReceived)
    /// 既定のアプリversionです。
    static let applicationVersion = try! AcquisitionApplicationVersion(marketingVersion: "fixture-1.0", buildVersion: "fixture-100")

    /// 既定値から指定項目だけを差し替えたmanifestを返します。
    ///
    /// 責務: 続行判定が比較する8項目とアダプター判定結果を個別に指定できるmanifestを作ります。
    /// - Parameters:
    ///   - manifestVersion: manifest version。
    ///   - applicationVersion: アプリversion。
    ///   - schemaVersion: schema契約version。
    ///   - pollingVersion: polling policy version。
    ///   - requests: 要求順。`nil` ならlegacy欠落。
    ///   - definitions: PID定義snapshot。`nil` なら2件の既定定義。
    ///   - platform: 取得platform。
    ///   - modelVersion: model入力manifest version。
    ///   - probe: アダプター判定結果。
    /// - Returns: 組み立てたmanifest。
    static func manifest(
        manifestVersion: Int? = 1,
        applicationVersion: AcquisitionApplicationVersion? = Self.applicationVersion,
        schemaVersion: Int? = 1,
        pollingVersion: Int? = 2,
        requests: [OBDPIDRequest]? = [firstRequest, secondRequest],
        definitions: [AcquisitionPIDDefinitionSnapshot]? = nil,
        platform: ConnectionSessionAcquisitionPlatform? = .macOS,
        modelVersion: Int? = 1,
        probe: AcquisitionAdapterProbeEvidence? = nil
    ) -> ConnectionSessionAcquisitionManifest {
        try! ConnectionSessionAcquisitionManifest(
            manifestVersion: manifestVersion,
            applicationVersion: applicationVersion,
            schemaContractVersion: schemaVersion,
            pollingPolicyVersion: pollingVersion,
            orderedRequestedPIDs: requests.map { try! OrderedAcquisitionPIDSet(requests: $0) },
            pidDefinitions: definitions ?? [definition(firstRequest), definition(secondRequest)],
            acquisitionPlatform: platform,
            modelInputManifestVersion: modelVersion,
            adapterProbeEvidence: probe
        )
    }

    /// 指定PIDの定義snapshotを返します。
    ///
    /// 責務: revisionだけを差し替えられる完全な定義snapshotを作ります。
    /// - Parameters:
    ///   - request: Service/PID。
    ///   - revision: 取得時revision。
    /// - Returns: 定義snapshot。
    static func definition(_ request: OBDPIDRequest, revision: Int = 1) -> AcquisitionPIDDefinitionSnapshot {
        try! AcquisitionPIDDefinitionSnapshot(
            request: request,
            capabilitySupport: .supported,
            isCollectionEnabled: true,
            definitionRevision: revision,
            requiredByteCount: 1,
            definitionIdentity: AcquisitionPIDDefinitionIdentity(canonicalizationVersion: 1, expression: "A"),
            unit: "unit",
            validityRange: AcquisitionPIDValidityRange.inclusive(minimum: 0, maximum: 255)
        )
    }
}
