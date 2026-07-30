import XCTest
@testable import ProjectZD8

/// 取得manifestの順序付きPID集合契約を検証します。
final class OrderedAcquisitionPIDSetTests: XCTestCase {
    /// 入力されたService/PID順を保持します。
    ///
    /// 責務: 順序付きPID集合が要素を並べ替えないことを確認します。
    func testPreservesRequestedPIDOrder() throws {
        let requests = [OBDPIDRequest(service: 1, pid: 12), OBDPIDRequest(service: 1, pid: 5)]

        XCTAssertEqual(try OrderedAcquisitionPIDSet(requests: requests).requests, requests)
    }

    /// 同じService/PIDの重複を拒否します。
    ///
    /// 責務: ordered PID setが重複を黙って除去しないことを確認します。
    func testRejectsDuplicatePID() {
        let request = OBDPIDRequest(service: 1, pid: 12)

        XCTAssertThrowsError(try OrderedAcquisitionPIDSet(requests: [request, request])) {
            XCTAssertEqual($0 as? OrderedAcquisitionPIDSetError, .duplicateRequest)
        }
    }

    /// 対応状態と収集選択を別軸で保持します。
    ///
    /// 責務: supported PIDでも収集無効を表現できることを確認します。
    func testSeparatesCapabilitySupportFromCollectionSelection() throws {
        let snapshot = try AcquisitionPIDDefinitionSnapshot(
            request: OBDPIDRequest(service: 1, pid: 12),
            capabilitySupport: .supported,
            isCollectionEnabled: false,
            definitionRevision: 1,
            requiredByteCount: 2,
            definitionIdentity: AcquisitionPIDDefinitionIdentity(canonicalizationVersion: 1, expression: "(A * 256 + B) / 4"),
            unit: "rpm",
            validityRange: AcquisitionPIDValidityRange.inclusive(minimum: 0, maximum: 16_383.75)
        )

        XCTAssertEqual(snapshot.capabilitySupport, .supported)
        XCTAssertFalse(try XCTUnwrap(snapshot.isCollectionEnabled))
    }
}
