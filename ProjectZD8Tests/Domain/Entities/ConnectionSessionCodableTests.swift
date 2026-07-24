import Foundation
import XCTest
@testable import ProjectZD8

/// 接続セッションの転送互換性を検証します。
final class ConnectionSessionCodableTests: XCTestCase {
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
