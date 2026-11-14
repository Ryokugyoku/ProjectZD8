import Foundation
import XCTest
@testable import ProjectZD8

/// 未登録車両(車両なしのセッション)でも、未登録車両用のcapability証跡で取得manifestが確定し、Rawが保存されることをGRDBで検証します。
@MainActor
final class ConnectionSessionAcquisitionRecorderUnregisteredTests: XCTestCase {
    /// 型名を短く参照するための別名です。
    private typealias Fixture = ConnectionSessionAcquisitionRecorderFixture

    /// 車両なしのセッションで、未登録車両用の証跡を渡した開始が証跡不足にならずにmanifestを確定し、記録したRawを保存します。
    ///
    /// 責務: manifestの要求順・PIDごとの対応と収集選択・Rawの保存と、セッションが車両なしであることを確認します。
    func testUnregisteredEvidenceConfirmsManifestAndRecords() async throws {
        let fixture = try Fixture(storage: .grdb)
        let requests = Fixture.definitions.map { OBDPIDRequest(service: $0.service, pid: $0.pid) }

        try await fixture.recorder.start(
            LiveTelemetryAcquisitionStartInput(
                generation: 1,
                definitions: Fixture.definitions,
                capabilities: requests.map(ConnectionSessionAcquisitionPIDCapabilityInput.unregisteredVehicleSupported),
                orderedRequests: requests
            )
        )
        try await fixture.respondedRound(0, payload: 7)
        try await fixture.recorder.flush(.backgroundTransition, generation: 1)

        let manifest = try fixture.acquisition.manifest(for: fixture.sessionID)
        XCTAssertEqual(manifest.orderedRequestedPIDs?.requests, requests)
        XCTAssertEqual(manifest.pidDefinitions.map(\.capabilitySupport), [.supported, .supported])
        XCTAssertEqual(manifest.pidDefinitions.map(\.isCollectionEnabled), [true, true])
        XCTAssertEqual(try fixture.storedRaws().map(\.payload), [[7]])
        XCTAssertNil(try fixture.sessions.sessions(for: "account").first { $0.id == fixture.sessionID }?.vehicle)
    }

    /// 未登録車両用の証跡でも、定義より証跡が少なければmanifestを確定せずに証跡不足で失敗し、区間も始めません。
    ///
    /// 責務: 未登録車両の経路で証跡と定義の照合が省かれていないことを確認します。
    func testMissingUnregisteredEvidenceIsRejected() async throws {
        let fixture = try Fixture(storage: .grdb)
        let requests = Fixture.definitions.map { OBDPIDRequest(service: $0.service, pid: $0.pid) }

        do {
            try await fixture.recorder.start(
                LiveTelemetryAcquisitionStartInput(
                    generation: 1,
                    definitions: Fixture.definitions,
                    capabilities: [ConnectionSessionAcquisitionPIDCapabilityInput.unregisteredVehicleSupported(requests[0])],
                    orderedRequests: requests
                )
            )
            XCTFail("証跡が足りないのに開始が成功しました")
        } catch {
            XCTAssertEqual(error as? CreateConnectionSessionAcquisitionManifestError, .capabilityEvidenceMissing)
        }

        XCTAssertThrowsError(try fixture.acquisition.manifest(for: fixture.sessionID))
        XCTAssertEqual(try fixture.segments.segments(for: fixture.sessionID), [])
    }
}
