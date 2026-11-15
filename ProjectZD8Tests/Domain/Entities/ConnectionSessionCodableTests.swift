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

    // MARK: - observedVIN

    /// 旧来の符号化形式から変わってはならないセッションのJSONキー一覧です。`observedVIN` だけが追加キーです。
    private static let legacyKeys: Set<String> = [
        "id", "accountIdentifier", "startedAt", "endedAt", "endReason", "stopReviewDecision", "vehicle",
        "acquisitionDevice", "startingOdometerKilometers", "endingOdometerKilometers", "distanceSourceModelCode",
        "rawLogSummary"
    ]

    /// 全任意項目を埋めた終了済みセッションを生成します。
    ///
    /// 責務: 符号化キーの検証で省略されるキーが出ないよう、全任意項目に値を持つ1件のセッションを返します。
    /// - Parameter observedVIN: 設定する観測VIN。
    /// - Returns: 全任意項目に値を持つセッション。
    private func fullSession(observedVIN: String?) -> ConnectionSession {
        var session = ConnectionSession(
            accountIdentifier: "account",
            startedAt: Date(timeIntervalSince1970: 100),
            vehicle: ConnectionSessionVehicle(id: VehicleID(), name: "BRZ", displayIdentifier: "ZD8"),
            acquisitionDevice: ConnectionSessionAcquisitionDevice(platform: .iPhone, name: "iPhone"),
            observedVIN: observedVIN
        )
        session.endedAt = Date(timeIntervalSince1970: 200)
        session.endReason = .userDisconnected
        session.stopReviewDecision = .userInitiated
        session.startingOdometerKilometers = 1
        session.endingOdometerKilometers = 2
        session.distanceSourceModelCode = "ZD8"
        return session
    }

    /// セッションを符号化し、JSONオブジェクトとして返します。
    ///
    /// 責務: 1件のセッションを `JSONEncoder` で符号化し、キー操作できる辞書へ変換します。
    /// - Parameter session: 符号化するセッション。
    /// - Returns: 符号化結果のJSONオブジェクト。
    /// - Throws: 符号化または辞書変換の失敗。
    private func encodedObject(_ session: ConnectionSession) throws -> [String: Any] {
        let encoded = try JSONEncoder().encode(session)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    }

    /// JSONオブジェクトからセッションを復号します。
    ///
    /// 責務: 手で書き換えたJSON辞書を `JSONDecoder` でDomainセッションへ戻します。
    /// - Parameter object: 復号するJSONオブジェクト。
    /// - Returns: 復号したセッション。
    /// - Throws: 直列化または復号の失敗。
    private func decode(_ object: [String: Any]) throws -> ConnectionSession {
        try JSONDecoder().decode(ConnectionSession.self, from: JSONSerialization.data(withJSONObject: object))
    }

    /// `observedVIN` キーを持たない旧JSONは `nil` として復号でき、他の項目は保たれます。
    ///
    /// 責務: 観測VIN追加前のPayloadを後方互換に復号できることを確認します。
    func testDecodeLegacyPayloadWithoutObservedVINKeyYieldsNil() throws {
        let original = fullSession(observedVIN: "JF1ZD8")
        var object = try encodedObject(original)
        object.removeValue(forKey: "observedVIN")

        let decoded = try decode(object)

        XCTAssertNil(decoded.observedVIN)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.vehicle, original.vehicle)
        XCTAssertEqual(decoded.acquisitionDevice, original.acquisitionDevice)
        XCTAssertEqual(decoded.distanceSourceModelCode, "ZD8")
    }

    /// 観測VINは符号化→復号で同じ値に戻り、セッション全体も等しくなります。
    ///
    /// 責務: 正規化済みの観測VINが往復で失われないことを確認します。
    func testObservedVINRoundTripsThroughJSON() throws {
        let original = fullSession(observedVIN: "jf1 ZD8abc")

        let decoded = try JSONDecoder().decode(ConnectionSession.self, from: JSONEncoder().encode(original))

        XCTAssertEqual(decoded.observedVIN, "jf1 ZD8abc")
        XCTAssertEqual(decoded, original)
    }

    /// 観測VINなしのセッションは往復後も `nil` です。
    ///
    /// 責務: `nil` の往復で空文字などの値が生じないことを確認します。
    func testNilObservedVINRoundTripsThroughJSON() throws {
        let original = fullSession(observedVIN: nil)

        let decoded = try JSONDecoder().decode(ConnectionSession.self, from: JSONEncoder().encode(original))

        XCTAssertNil(decoded.observedVIN)
        XCTAssertEqual(decoded, original)
    }

    /// 復号時も前後の空白・改行を除き、内側の空白と大文字小文字は保ちます。
    ///
    /// 責務: 外部から届いた未正規化の観測VINが復号経路で正規化されることを確認します。
    func testDecodeTrimsObservedVINAndPreservesInnerContent() throws {
        var object = try encodedObject(fullSession(observedVIN: nil))
        object["observedVIN"] = " \n\tjf1 Zd8\r\n "

        XCTAssertEqual(try decode(object).observedVIN, "jf1 Zd8")
    }

    /// 復号時に空白類だけの観測VINは `nil` になります。
    ///
    /// 責務: 復号経路で空白だけの値が非空として残らないことを確認します。
    func testDecodeWhitespaceOnlyObservedVINYieldsNil() throws {
        var object = try encodedObject(fullSession(observedVIN: nil))
        object["observedVIN"] = " \t\n "

        XCTAssertNil(try decode(object).observedVIN)
    }

    /// 復号時に空文字の観測VINは `nil` になります。
    ///
    /// 責務: 復号経路の境界値(長さ0)が `nil` へ変換されることを確認します。
    func testDecodeEmptyObservedVINYieldsNil() throws {
        var object = try encodedObject(fullSession(observedVIN: nil))
        object["observedVIN"] = ""

        XCTAssertNil(try decode(object).observedVIN)
    }

    /// 全項目を持つセッションの符号化キーは旧来のキー名に `observedVIN` を加えたものです。
    ///
    /// 責務: 既存キー名が変わらず、追加キー名が `observedVIN` であることを確認します。
    func testEncodedKeysKeepLegacyNamesAndAddObservedVIN() throws {
        let object = try encodedObject(fullSession(observedVIN: "JF1ZD8"))

        XCTAssertEqual(Set(object.keys), Self.legacyKeys.union(["observedVIN"]))
        XCTAssertEqual(object["observedVIN"] as? String, "JF1ZD8")
    }

    /// 観測VINなしのセッションは旧来と同じキー集合で符号化されます。
    ///
    /// 責務: 観測VINが無い既存形のPayloadが旧形式から変化しないことを確認します。
    func testEncodedKeysWithoutObservedVINMatchLegacyShape() throws {
        let object = try encodedObject(fullSession(observedVIN: nil))

        XCTAssertEqual(Set(object.keys), Self.legacyKeys)
    }
}
