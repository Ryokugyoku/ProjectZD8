import Foundation
import XCTest
@testable import ProjectZD8

/// 車両プロフィールの保存形式互換性を検証します。
@MainActor
final class VehicleProfileCodableTests: XCTestCase {
    /// OBD由来識別子追加前の保存データを復元します。
    ///
    /// 責務: `obdIdentifier` を持たない既存JSONが引き続き車両プロフィールへ復号できることを確認します。
    func testDecodesLegacyProfileWithoutOBDIdentifier() throws {
        let profile = try makeProfile(obdIdentifier: nil)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as? [String: Any]
        )
        object.removeValue(forKey: "obdIdentifier")

        let decoded = try JSONDecoder().decode(
            VehicleProfile.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertEqual(decoded, profile)
        XCTAssertNil(decoded.obdIdentifier)
    }

    /// 非VINのOBD由来識別子を保存して復元します。
    ///
    /// 責務: VINを持たない登録車両のOBD由来識別子がCodable往復で保持されることを確認します。
    func testRoundTripsProfileWithOBDIdentifier() throws {
        let profile = try makeProfile(obdIdentifier: "ZD81234567")

        let decoded = try JSONDecoder().decode(
            VehicleProfile.self,
            from: JSONEncoder().encode(profile)
        )

        XCTAssertEqual(decoded, profile)
        XCTAssertEqual(decoded.displayIdentifier, "ZD81234567")
    }

    /// 固定値の車両プロフィールを生成します。
    ///
    /// 責務: 保存形式テストで比較する1台分の再現可能なプロフィールを生成します。
    /// - Parameter obdIdentifier: VINとは分離して保存するOBD由来識別子。
    /// - Returns: 固定日時と固定IDを持つテスト用プロフィール。
    /// - Throws: テスト用UUIDリテラルを生成できない場合の `XCTUnwrap` エラー。
    private func makeProfile(obdIdentifier: String?) throws -> VehicleProfile {
        VehicleProfile(
            id: VehicleID(rawValue: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))),
            vin: obdIdentifier == nil ? "1D4GP00R55B123456" : "",
            obdIdentifier: obdIdentifier,
            name: "テスト車両",
            updatedAt: Date(timeIntervalSince1970: 100)
        )
    }
}
