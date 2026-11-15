import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// `GRDBConnectionSessionRepository` の観測VIN保存、未紐付け照会、VINによる車両紐付けを検証します。
@MainActor
final class GRDBConnectionSessionRepositoryObservedVINTests: XCTestCase {
    /// 照合対象の代表VINです。
    private static let vin = "JF1ZD8ABC12345678"
    /// 照合対象と異なるVINです。
    private static let otherVIN = "JF1ZD8XYZ87654321"

    /// 紐付け先の登録車両です。
    private let registered = ConnectionSessionVehicle(id: VehicleID(), name: "BRZ", displayIdentifier: "JF1ZD8ABC12345678")
    /// 既に別のセッションへ設定済みの車両です。
    private let previous = ConnectionSessionVehicle(id: VehicleID(), name: "86", displayIdentifier: "ZN8")

    /// 指定条件の未終了セッションを保存します。
    ///
    /// 責務: アカウント・開始日時・車両・観測VINを指定した1件のセッションを実Repository経由で保存します。
    /// - Parameters:
    ///   - fixtures: 保存先。
    ///   - account: 所有アカウント識別子。
    ///   - startedAt: 開始日時のUNIX秒。
    ///   - vehicle: 設定する車両。
    ///   - vin: 設定する観測VIN。
    /// - Returns: 保存したセッション。
    /// - Throws: 保存の失敗。
    @discardableResult
    private func seed(
        _ fixtures: GRDBConnectionSessionRepositoryFixtures,
        account: String = "account",
        startedAt: TimeInterval = 100,
        vehicle: ConnectionSessionVehicle? = nil,
        vin: String?
    ) throws -> ConnectionSession {
        let session = ConnectionSession(
            accountIdentifier: account,
            startedAt: Date(timeIntervalSince1970: startedAt),
            vehicle: vehicle,
            observedVIN: vin
        )
        try fixtures.repository.save(session)
        return session
    }

    /// 保存済みセッションをIDで読み戻します。
    ///
    /// 責務: 指定アカウントの一覧から1件のセッションを取り出します。
    /// - Parameters:
    ///   - fixtures: 読取元。
    ///   - session: 読み戻すセッション。
    /// - Returns: 読み戻したセッション。
    /// - Throws: 読取失敗、または該当なしの場合の `XCTUnwrap` 失敗。
    private func reload(
        _ fixtures: GRDBConnectionSessionRepositoryFixtures,
        _ session: ConnectionSession
    ) throws -> ConnectionSession {
        try XCTUnwrap(try fixtures.repository.sessions(for: session.accountIdentifier).first { $0.id == session.id })
    }

    // MARK: - save / sessions(for:)

    /// 観測VINあり・車両なしのセッションは保存後に同じ観測VINで読み戻せます。
    ///
    /// 責務: 観測VIN列への保存とDomainへの復元が往復することを確認します。
    func testSaveRoundTripsObservedVINWithoutVehicle() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let session = try seed(fixtures, vin: "jf1 Zd8abc")

        let loaded = try reload(fixtures, session)

        XCTAssertEqual(loaded.observedVIN, "jf1 Zd8abc")
        XCTAssertNil(loaded.vehicle)
        XCTAssertEqual(try fixtures.storedRecord(session.id).observedVIN, "jf1 Zd8abc")
    }

    /// 観測VINなしの既存形セッションは観測VIN列がNULLのまま従来どおり読み戻せます。
    ///
    /// 責務: 観測VINを持たない保存で空文字などが書かれず、車両情報も従来どおり往復することを確認します。
    func testSaveWithoutObservedVINKeepsNullColumnAndVehicle() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let session = try seed(fixtures, vehicle: registered, vin: nil)

        let loaded = try reload(fixtures, session)

        XCTAssertNil(loaded.observedVIN)
        XCTAssertEqual(loaded.vehicle, registered)
        XCTAssertNil(try fixtures.storedRecord(session.id).observedVIN)
    }

    // MARK: - unassignedSessionsWithObservedVIN(for:)

    /// 照会は車両未設定かつ観測VINありのセッションだけを開始日時の新しい順で返します。
    ///
    /// 責務: 車両設定済み・観測VINなし・別アカウントを除外し、降順に並ぶことを確認します。
    func testUnassignedSessionsReturnOnlyUnassignedWithVINNewestFirst() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let older = try seed(fixtures, startedAt: 100, vin: Self.vin)
        let newer = try seed(fixtures, startedAt: 300, vin: Self.otherVIN)
        let middle = try seed(fixtures, startedAt: 200, vin: Self.vin.lowercased())
        try seed(fixtures, startedAt: 400, vehicle: previous, vin: Self.vin)
        try seed(fixtures, startedAt: 500, vin: nil)
        try seed(fixtures, account: "other", startedAt: 600, vin: Self.vin)

        let loaded = try fixtures.repository.unassignedSessionsWithObservedVIN(for: "account")

        XCTAssertEqual(loaded.map(\.id), [newer.id, middle.id, older.id])
        XCTAssertEqual(loaded.map(\.observedVIN), [Self.otherVIN, Self.vin.lowercased(), Self.vin])
        XCTAssertTrue(loaded.allSatisfy { $0.vehicle == nil })
    }

    /// 該当するセッションが無いアカウントでは空配列を返します。
    ///
    /// 責務: 車両設定済みと観測VINなしだけのアカウント、および未知アカウントで空になることを確認します。
    func testUnassignedSessionsReturnEmptyWhenNothingMatches() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        try seed(fixtures, startedAt: 100, vehicle: previous, vin: Self.vin)
        try seed(fixtures, startedAt: 200, vin: nil)

        XCTAssertEqual(try fixtures.repository.unassignedSessionsWithObservedVIN(for: "account"), [])
        XCTAssertEqual(try fixtures.repository.unassignedSessionsWithObservedVIN(for: "unknown"), [])
    }

    // MARK: - assignVehicle(_:toUnassignedSessionsWithObservedVIN:for:)

    /// 大文字小文字だけが異なる観測VINの未紐付けセッション全件へ車両を設定し、件数を返します。
    ///
    /// 責務: NOCASE一致の全件更新、車両ID・名称・表示識別子の設定、観測VINの保持を確認します。
    func testAssignVehicleUpdatesAllCaseInsensitiveMatchesAndKeepsObservedVIN() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let upper = try seed(fixtures, startedAt: 100, vin: Self.vin)
        let lower = try seed(fixtures, startedAt: 200, vin: Self.vin.lowercased())

        let count = try fixtures.repository.assignVehicle(registered, toUnassignedSessionsWithObservedVIN: Self.vin, for: "account")

        XCTAssertEqual(count, 2)
        XCTAssertEqual(try reload(fixtures, upper).vehicle, registered)
        XCTAssertEqual(try reload(fixtures, lower).vehicle, registered)
        XCTAssertEqual(try reload(fixtures, upper).observedVIN, Self.vin)
        XCTAssertEqual(try reload(fixtures, lower).observedVIN, Self.vin.lowercased())
        XCTAssertEqual(try fixtures.repository.unassignedSessionsWithObservedVIN(for: "account"), [])
    }

    /// 引数のVINは前後の空白・改行を除いてから照合します。
    ///
    /// 責務: 前後に空白類と小文字を含む引数でも一致セッションへ紐付けられることを確認します。
    func testAssignVehicleTrimsArgumentBeforeMatching() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let session = try seed(fixtures, vin: Self.vin)

        let count = try fixtures.repository.assignVehicle(
            registered,
            toUnassignedSessionsWithObservedVIN: " \t\(Self.vin.lowercased())\n ",
            for: "account"
        )

        XCTAssertEqual(count, 1)
        XCTAssertEqual(try reload(fixtures, session).vehicle, registered)
    }

    /// 車両設定済みのセッションは同じVINでも変更しません。
    ///
    /// 責務: 既存の車両情報が上書きされず、件数にも含まれないことを確認します。
    func testAssignVehicleLeavesAlreadyAssignedSessionUnchanged() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let assigned = try seed(fixtures, startedAt: 100, vehicle: previous, vin: Self.vin)
        let unassigned = try seed(fixtures, startedAt: 200, vin: Self.vin)

        let count = try fixtures.repository.assignVehicle(registered, toUnassignedSessionsWithObservedVIN: Self.vin, for: "account")

        XCTAssertEqual(count, 1)
        XCTAssertEqual(try reload(fixtures, assigned).vehicle, previous)
        XCTAssertEqual(try reload(fixtures, unassigned).vehicle, registered)
    }

    /// 別VIN・別アカウント・観測VINなしのセッションは変更しません。
    ///
    /// 責務: 照合条件のVIN・アカウント・観測VIN有無がそれぞれ除外に効くことを確認します。
    func testAssignVehicleLeavesOtherVINOtherAccountAndMissingVINUnchanged() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let target = try seed(fixtures, startedAt: 100, vin: Self.vin)
        let otherVIN = try seed(fixtures, startedAt: 200, vin: Self.otherVIN)
        let otherAccount = try seed(fixtures, account: "other", startedAt: 300, vin: Self.vin)
        let missingVIN = try seed(fixtures, startedAt: 400, vin: nil)

        let count = try fixtures.repository.assignVehicle(registered, toUnassignedSessionsWithObservedVIN: Self.vin, for: "account")

        XCTAssertEqual(count, 1)
        XCTAssertEqual(try reload(fixtures, target).vehicle, registered)
        XCTAssertNil(try reload(fixtures, otherVIN).vehicle)
        XCTAssertNil(try reload(fixtures, otherAccount).vehicle)
        XCTAssertNil(try reload(fixtures, missingVIN).vehicle)
        XCTAssertEqual(try reload(fixtures, otherAccount).observedVIN, Self.vin)
    }

    /// 一致するセッションが無い場合は0件で、何も変更しません。
    ///
    /// 責務: 一致なしを失敗ではなく0件として返すことを確認します。
    func testAssignVehicleReturnsZeroWhenNothingMatches() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let session = try seed(fixtures, vin: Self.otherVIN)

        let count = try fixtures.repository.assignVehicle(registered, toUnassignedSessionsWithObservedVIN: Self.vin, for: "account")

        XCTAssertEqual(count, 0)
        XCTAssertNil(try reload(fixtures, session).vehicle)
    }

    /// 同じ紐付けを再実行すると0件で、1回目の結果を保ちます。
    ///
    /// 責務: 紐付けが冪等で、再実行が別の車両情報を書かないことを確認します。
    func testAssignVehicleIsIdempotentOnRerun() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let session = try seed(fixtures, vin: Self.vin)
        XCTAssertEqual(
            try fixtures.repository.assignVehicle(registered, toUnassignedSessionsWithObservedVIN: Self.vin, for: "account"),
            1
        )

        let rerun = try fixtures.repository.assignVehicle(registered, toUnassignedSessionsWithObservedVIN: Self.vin, for: "account")

        XCTAssertEqual(rerun, 0)
        XCTAssertEqual(try reload(fixtures, session).vehicle, registered)
    }

    /// 空白類だけのVINは `invalidState` で拒否し、何も変更しません。
    ///
    /// 責務: 空白だけの引数が全件一致などに化けず型付きエラーになることを確認します。
    func testAssignVehicleRejectsWhitespaceOnlyVINWithInvalidState() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let session = try seed(fixtures, vin: Self.vin)

        assertThrowsError(ConnectionSessionRepositoryError.invalidState) {
            _ = try fixtures.repository.assignVehicle(registered, toUnassignedSessionsWithObservedVIN: " \t\n ", for: "account")
        }
        XCTAssertNil(try reload(fixtures, session).vehicle)
    }

    /// 空文字のVINも `invalidState` で拒否します。
    ///
    /// 責務: 空白だけの境界値である長さ0の引数も同じエラーになることを確認します。
    func testAssignVehicleRejectsEmptyVINWithInvalidState() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()

        assertThrowsError(ConnectionSessionRepositoryError.invalidState) {
            _ = try fixtures.repository.assignVehicle(registered, toUnassignedSessionsWithObservedVIN: "", for: "account")
        }
    }
}
