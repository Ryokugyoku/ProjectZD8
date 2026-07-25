import Foundation
import XCTest
@testable import ProjectZD8

/// 接続セッションの転送互換性を検証します。
final class ConnectionSessionCodableTests: XCTestCase {
    /// Raw転送Payloadが表示メタデータを含まず安定セッションIDだけを保持します。
    ///
    /// 責務: 接続セッションから生成したRaw転送JSONを識別情報とRawログだけの形式として検証します。
    func testRawTransferPackageEncodesOnlyStableOwnershipAndEntries() throws {
        var session = ConnectionSession(accountIdentifier: "account", startedAt: Date(timeIntervalSince1970: 100))
        session.endedAt = Date(timeIntervalSince1970: 200)
        session.endReason = .userDisconnected
        let package = ConnectionSessionTransferPackage(session: session, entries: [])

        let encoded = try JSONEncoder().encode(package)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let decoded = try JSONDecoder().decode(ConnectionSessionTransferPackage.self, from: encoded)

        XCTAssertEqual(Set(object.keys), ["accountIdentifier", "entries", "sessionID"])
        XCTAssertEqual(decoded.sessionID, session.id)
        XCTAssertEqual(decoded.accountIdentifier, session.accountIdentifier)
        XCTAssertEqual(decoded.entries, [])
    }

    /// 旧Payloadに停止確認キーがなくても未確認状態として復元します。
    ///
    /// 責務: 停止確認追加前の接続セッションJSONを後方互換なDomain状態へ復元できることを確認します。
    func testDecodeLegacyPayloadWithoutStopReviewDecision() throws {
        var session = ConnectionSession(accountIdentifier: "account", startedAt: Date(timeIntervalSince1970: 100))
        session.endedAt = Date(timeIntervalSince1970: 200)
        session.endReason = .connectionLost
        let encoded = try JSONEncoder().encode(session)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "stopReviewDecision")
        object.removeValue(forKey: "acquisitionDevice")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(ConnectionSession.self, from: legacyData)

        XCTAssertNil(decoded.stopReviewDecision)
        XCTAssertNil(decoded.acquisitionDevice)
        XCTAssertTrue(decoded.needsStopReview)
        XCTAssertEqual(decoded.status, .interrupted)
    }
}
