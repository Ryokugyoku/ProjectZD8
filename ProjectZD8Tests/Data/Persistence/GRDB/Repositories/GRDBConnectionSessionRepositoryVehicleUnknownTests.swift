import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// `GRDBConnectionSessionRepository` の車両不明ログ(終了済み・車両なし・観測VINなし)の照会と、登録車両への紐付けを検証します。
///
/// 仕様: U4 受け入れ条件 13・17。記録中・観測VINあり・車両あり・別アカウントの行は、照会にも更新にも入りません。
@MainActor
final class GRDBConnectionSessionRepositoryVehicleUnknownTests: XCTestCase {
    /// 紐付け先の登録車両です。
    private let registered = ConnectionSessionVehicle(id: VehicleID(), name: "BRZ", displayIdentifier: "JF1ZD8ABC12345678")
    /// 既に別のセッションへ設定済みの車両です。
    private let previous = ConnectionSessionVehicle(id: VehicleID(), name: "86", displayIdentifier: "ZN8")

    /// 対象と対象外の行をまとめた保存結果です。
    private struct Seeded {
        /// 対象の車両不明ログ(開始の古い順)です。
        let targets: [ConnectionSession]
        /// 記録中(未終了)・車両なし・観測VINなしの行です。
        let active: ConnectionSession
        /// 終了済み・車両なし・観測VINありの行です。
        let observedVIN: ConnectionSession
        /// 終了済み・車両あり・観測VINなしの行です。
        let withVehicle: ConnectionSession
        /// 別アカウントの終了済み・車両なし・観測VINなしの行です。
        let otherAccount: ConnectionSession

        /// 対象外の行です。
        var excluded: [ConnectionSession] { [active, observedVIN, withVehicle, otherAccount] }
    }

    /// 1件のセッションを保存します。終了日時があれば、未終了で保存してから終了を保存します。
    ///
    /// 責務: 実Repository経由で指定条件のセッション行を作ります。
    /// - Parameters:
    ///   - fixtures: 保存先。
    ///   - account: 所有アカウント識別子。
    ///   - startedAt: 開始日時のUNIX秒。
    ///   - ended: 終了済みにするか。
    ///   - vehicle: 設定する車両。
    ///   - vin: 設定する観測VIN。
    /// - Returns: 保存したセッション。
    /// - Throws: 保存の失敗。
    private func seed(
        _ fixtures: GRDBConnectionSessionRepositoryFixtures,
        account: String = "account",
        startedAt: TimeInterval,
        ended: Bool = true,
        vehicle: ConnectionSessionVehicle? = nil,
        vin: String? = nil
    ) throws -> ConnectionSession {
        var session = ConnectionSession(
            accountIdentifier: account, startedAt: Date(timeIntervalSince1970: startedAt), vehicle: vehicle, observedVIN: vin
        )
        try fixtures.repository.save(session)
        guard ended else { return session }
        session.endedAt = Date(timeIntervalSince1970: startedAt + 10)
        session.endReason = .connectionLost
        try fixtures.repository.save(session)
        return session
    }

    /// 対象3件と対象外4件を保存します。
    ///
    /// 責務: 照会と更新の対象条件を区別できる行の組を作ります。
    /// - Parameter fixtures: 保存先。
    /// - Returns: 保存結果。
    /// - Throws: 保存の失敗。
    private func seedMixed(_ fixtures: GRDBConnectionSessionRepositoryFixtures) throws -> Seeded {
        let targets = try [100, 300, 200].map { try seed(fixtures, startedAt: TimeInterval($0)) }
        return Seeded(
            targets: targets,
            active: try seed(fixtures, startedAt: 400, ended: false),
            observedVIN: try seed(fixtures, startedAt: 500, vin: "JF1ZD8ABC12345678"),
            withVehicle: try seed(fixtures, startedAt: 600, vehicle: previous),
            otherAccount: try seed(fixtures, account: "other", startedAt: 700)
        )
    }

    /// 保存済みの車両IDの列を返します。
    ///
    /// 責務: Domain補正を経ずに1行の `vehicleID` を読みます。
    /// - Parameters:
    ///   - fixtures: 読取元。
    ///   - session: 読む行。
    /// - Returns: 車両IDの列の値。
    /// - Throws: 読取失敗。
    private func storedVehicleID(_ fixtures: GRDBConnectionSessionRepositoryFixtures, _ session: ConnectionSession) throws -> String? {
        try fixtures.storedRecord(session.id).vehicleID
    }

    // MARK: - vehicleUnknownSessions(for:)

    /// 照会は終了済み・車両なし・観測VINなし・同じアカウントの行だけを、開始日時の新しい順で返します。
    ///
    /// 責務: 記録中・観測VINあり・車両あり・別アカウントを除き、降順に並ぶことを確認します。
    func testVehicleUnknownSessionsReturnOnlyTargetsNewestFirst() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let seeded = try seedMixed(fixtures)

        let loaded = try fixtures.repository.vehicleUnknownSessions(for: "account")

        XCTAssertEqual(loaded.map(\.id), [seeded.targets[1].id, seeded.targets[2].id, seeded.targets[0].id])
        XCTAssertTrue(loaded.allSatisfy { $0.vehicle == nil && $0.observedVIN == nil && $0.endedAt != nil })
    }

    /// 該当が無いアカウントでは空の一覧を返します。
    ///
    /// 責務: 対象外の行だけのアカウントと未知のアカウントで空になることを確認します。
    func testVehicleUnknownSessionsReturnEmptyWhenNothingMatches() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        _ = try seed(fixtures, startedAt: 100, ended: false)
        _ = try seed(fixtures, startedAt: 200, vehicle: previous)

        XCTAssertEqual(try fixtures.repository.vehicleUnknownSessions(for: "account"), [])
        XCTAssertEqual(try fixtures.repository.vehicleUnknownSessions(for: "unknown"), [])
    }

    // MARK: - assignVehicle(_:toVehicleUnknownSessions:for:)

    /// 選んだ対象のログだけへ車両を設定し、件数を返します。照会からは外れます。
    ///
    /// 責務: 3件のうち2件の紐付けで件数2・車両ID/名称/表示識別子の設定・選ばなかった1件の不変・照会結果1件を確認します(受け入れ条件 12)。
    func testAssignVehicleUpdatesSelectedTargets() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let seeded = try seedMixed(fixtures)
        let chosen = [seeded.targets[0], seeded.targets[1]]

        let count = try fixtures.repository.assignVehicle(registered, toVehicleUnknownSessions: chosen.map(\.id), for: "account")

        XCTAssertEqual(count, 2)
        for session in chosen {
            let record = try fixtures.storedRecord(session.id)
            XCTAssertEqual(record.vehicleID, registered.id.rawValue.uuidString.lowercased())
            XCTAssertEqual(record.vehicleName, registered.name)
            XCTAssertEqual(record.vehicleDisplayIdentifier, registered.displayIdentifier)
            XCTAssertNil(record.observedVIN)
        }
        XCTAssertNil(try storedVehicleID(fixtures, seeded.targets[2]))
        XCTAssertEqual(try fixtures.repository.vehicleUnknownSessions(for: "account").map(\.id), [seeded.targets[2].id])
    }

    /// 対象外の行(記録中・観測VINあり・車両あり・別アカウント)は、IDを指定しても更新しません。
    ///
    /// 責務: 対象外4件のIDだけの紐付けで件数0・各行の車両が元のままであることを確認します(受け入れ条件 13)。
    func testAssignVehicleNeverUpdatesExcludedRows() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let seeded = try seedMixed(fixtures)

        let count = try fixtures.repository.assignVehicle(registered, toVehicleUnknownSessions: seeded.excluded.map(\.id), for: "account")

        XCTAssertEqual(count, 0)
        XCTAssertNil(try storedVehicleID(fixtures, seeded.active))
        XCTAssertNil(try storedVehicleID(fixtures, seeded.observedVIN))
        XCTAssertNil(try storedVehicleID(fixtures, seeded.otherAccount))
        XCTAssertEqual(try storedVehicleID(fixtures, seeded.withVehicle), previous.id.rawValue.uuidString.lowercased())
        XCTAssertEqual(try fixtures.storedRecord(seeded.withVehicle.id).vehicleName, previous.name)
    }

    /// 対象と対象外のIDを混ぜた場合は、対象の行だけを更新して数えます。
    ///
    /// 責務: 対象1件+対象外4件の紐付けで件数1、対象外の行が変わらないことを確認します(受け入れ条件 13)。
    func testAssignVehicleWithMixedIDsCountsOnlyTargets() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let seeded = try seedMixed(fixtures)
        let ids = [seeded.targets[2].id] + seeded.excluded.map(\.id)

        let count = try fixtures.repository.assignVehicle(registered, toVehicleUnknownSessions: ids, for: "account")

        XCTAssertEqual(count, 1)
        XCTAssertEqual(try storedVehicleID(fixtures, seeded.targets[2]), registered.id.rawValue.uuidString.lowercased())
        XCTAssertNil(try storedVehicleID(fixtures, seeded.active))
        XCTAssertNil(try storedVehicleID(fixtures, seeded.otherAccount))
    }

    /// 別アカウントで呼んだ場合、このアカウントの対象のログは更新しません。
    ///
    /// 責務: 対象のIDを別アカウント指定で紐付けると件数0・行が不変であることを確認します(受け入れ条件 13)。
    func testAssignVehicleForOtherAccountDoesNotUpdate() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let seeded = try seedMixed(fixtures)

        let count = try fixtures.repository.assignVehicle(registered, toVehicleUnknownSessions: seeded.targets.map(\.id), for: "other")

        XCTAssertEqual(count, 0)
        for session in seeded.targets {
            XCTAssertNil(try storedVehicleID(fixtures, session))
        }
    }

    /// 空のID列では何も更新せず0を返します。
    ///
    /// 責務: 空配列の境界で全ての対象のログが不変であることを確認します。
    func testAssignVehicleWithEmptyIDsUpdatesNothing() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let seeded = try seedMixed(fixtures)

        XCTAssertEqual(try fixtures.repository.assignVehicle(registered, toVehicleUnknownSessions: [], for: "account"), 0)
        XCTAssertEqual(try fixtures.repository.vehicleUnknownSessions(for: "account").count, seeded.targets.count)
    }

    /// 存在しないIDだけでは何も更新せず0を返します。
    ///
    /// 責務: 保存されていないIDの紐付けで件数0・対象のログの件数が不変であることを確認します。
    func testAssignVehicleWithUnknownIDUpdatesNothing() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let seeded = try seedMixed(fixtures)

        XCTAssertEqual(try fixtures.repository.assignVehicle(registered, toVehicleUnknownSessions: [ConnectionSessionID()], for: "account"), 0)
        XCTAssertEqual(try fixtures.repository.vehicleUnknownSessions(for: "account").count, seeded.targets.count)
    }

    /// 同じログへ2回紐付けても、2回目は対象外(車両あり)なので更新しません。
    ///
    /// 責務: 1回目の件数1・2回目の件数0で、2回目の車両が1回目のままであることを確認します(受け入れ条件 13)。
    func testAssignVehicleTwiceDoesNotOverwrite() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let seeded = try seedMixed(fixtures)
        let target = seeded.targets[0]

        XCTAssertEqual(try fixtures.repository.assignVehicle(registered, toVehicleUnknownSessions: [target.id], for: "account"), 1)
        XCTAssertEqual(try fixtures.repository.assignVehicle(previous, toVehicleUnknownSessions: [target.id], for: "account"), 0)

        XCTAssertEqual(try storedVehicleID(fixtures, target), registered.id.rawValue.uuidString.lowercased())
    }
}
