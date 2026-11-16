import Foundation
import XCTest
@testable import ProjectZD8

/// `UserDefaultsAccountDeletionVehicleIDStore` の往復・アカウント分離・削除・不正値の扱いを検証します。
///
/// 仕様: 保存した車両IDを読み戻せる。アカウントごとに分離する。削除で消える。空配列の保存は控えを消す。復元できない値は無視する。
@MainActor
final class UserDefaultsAccountDeletionVehicleIDStoreTests: XCTestCase {
    /// このテストが作った UserDefaults スイート名です。終了時に消します。
    private var suiteNames: [String] = []

    /// テストで作ったスイートを消します。
    ///
    /// 責務: 他のテストや実環境へ値を残さないよう、作ったスイートの永続領域を削除します。
    override func tearDown() {
        for name in suiteNames {
            UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
        }
        suiteNames = []
        super.tearDown()
    }

    /// 専用の空スイートを作ります。
    ///
    /// 責務: 一意な名前のスイートを作り、終了時の削除対象に登録します。
    /// - Returns: 空の UserDefaults。
    private func makeSuite() throws -> UserDefaults {
        let name = "UserDefaultsAccountDeletionVehicleIDStoreTests.\(UUID().uuidString)"
        suiteNames.append(name)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// 未保存のアカウントは空配列を返すことを検証します。
    ///
    /// 責務: 空のスイートで控えが空であることを確認します。
    func testUnsetAccountHasNoPendingIDs() throws {
        let store = UserDefaultsAccountDeletionVehicleIDStore(defaults: try makeSuite())

        XCTAssertTrue(store.pendingVehicleIDs(for: "user").isEmpty)
    }

    /// 保存した車両IDを順序どおりに読め、別インスタンスからも読めることを検証します。
    ///
    /// 責務: 保存の往復と、同じスイートを使う別インスタンスでの読み戻しを確認します。
    func testSavedIDsRoundTripInOrderAcrossInstances() throws {
        let defaults = try makeSuite()
        let ids = [VehicleID(), VehicleID(), VehicleID()]

        UserDefaultsAccountDeletionVehicleIDStore(defaults: defaults).savePendingVehicleIDs(ids, for: "user")

        XCTAssertEqual(UserDefaultsAccountDeletionVehicleIDStore(defaults: defaults).pendingVehicleIDs(for: "user"), ids)
    }

    /// 保存は既存の控えを置き換えることを検証します。
    ///
    /// 責務: 2回目の保存が1回目へ追加されず、置き換わることを確認します。
    func testSaveReplacesPreviousIDs() throws {
        let store = UserDefaultsAccountDeletionVehicleIDStore(defaults: try makeSuite())
        let (first, second) = (VehicleID(), VehicleID())

        store.savePendingVehicleIDs([first], for: "user")
        store.savePendingVehicleIDs([second], for: "user")

        XCTAssertEqual(store.pendingVehicleIDs(for: "user"), [second])
    }

    /// アカウントごとに控えが分離されることを検証します。
    ///
    /// 責務: 別アカウントの保存・削除が互いに影響しないことを確認します。
    func testAccountsAreIsolated() throws {
        let store = UserDefaultsAccountDeletionVehicleIDStore(defaults: try makeSuite())
        let (mine, theirs) = (VehicleID(), VehicleID())
        store.savePendingVehicleIDs([mine], for: "user")
        store.savePendingVehicleIDs([theirs], for: "other")

        XCTAssertEqual(store.pendingVehicleIDs(for: "user"), [mine])
        XCTAssertEqual(store.pendingVehicleIDs(for: "other"), [theirs])

        store.clearPendingVehicleIDs(for: "user")

        XCTAssertTrue(store.pendingVehicleIDs(for: "user").isEmpty)
        XCTAssertEqual(store.pendingVehicleIDs(for: "other"), [theirs])
    }

    /// 削除で控えが消えることと、未保存のアカウントの削除が無害であることを検証します。
    ///
    /// 責務: 削除後に空になり、もう一度削除しても失敗しないことを確認します。
    func testClearRemovesIDsAndIsIdempotent() throws {
        let store = UserDefaultsAccountDeletionVehicleIDStore(defaults: try makeSuite())
        store.savePendingVehicleIDs([VehicleID()], for: "user")

        store.clearPendingVehicleIDs(for: "user")
        store.clearPendingVehicleIDs(for: "user")

        XCTAssertTrue(store.pendingVehicleIDs(for: "user").isEmpty)
    }

    /// 空配列の保存は、控えを消し、保存先に値を残さないことを検証します。
    ///
    /// 責務: 既存の控えが空配列の保存で消え、保存先のキーも増えないことを確認します。
    func testSavingEmptyArrayRemovesPendingIDs() throws {
        let defaults = try makeSuite()
        let store = UserDefaultsAccountDeletionVehicleIDStore(defaults: defaults)
        let baseline = Set(defaults.dictionaryRepresentation().keys)
        store.savePendingVehicleIDs([VehicleID()], for: "user")

        store.savePendingVehicleIDs([], for: "user")

        XCTAssertTrue(store.pendingVehicleIDs(for: "user").isEmpty)
        XCTAssertEqual(Set(defaults.dictionaryRepresentation().keys), baseline)
    }

    /// 復元できない保存値は無視し、復元できる値だけを返すことを検証します。
    ///
    /// 責務: UUID でない文字列と、文字列配列でない値の扱いを確認します。
    func testInvalidStoredValuesAreIgnored() throws {
        let defaults = try makeSuite()
        let store = UserDefaultsAccountDeletionVehicleIDStore(defaults: defaults)
        let baseline = Set(defaults.dictionaryRepresentation().keys)
        let valid = VehicleID()
        store.savePendingVehicleIDs([valid], for: "user")
        let key = try XCTUnwrap(Set(defaults.dictionaryRepresentation().keys).subtracting(baseline).first)

        defaults.set([valid.rawValue.uuidString, "not-a-uuid", ""], forKey: key)
        XCTAssertEqual(store.pendingVehicleIDs(for: "user"), [valid])

        defaults.set(["not-a-uuid"], forKey: key)
        XCTAssertTrue(store.pendingVehicleIDs(for: "user").isEmpty)

        defaults.set(42, forKey: key)
        XCTAssertTrue(store.pendingVehicleIDs(for: "user").isEmpty)
    }

    /// 保存キーにアカウント識別子を平文で含めないことを検証します。
    ///
    /// 責務: 識別子を保存した後のキーに、その識別子の文字列が含まれないことを確認します。
    func testStoredKeyDoesNotContainAccountIdentifierInPlainText() throws {
        let defaults = try makeSuite()
        let store = UserDefaultsAccountDeletionVehicleIDStore(defaults: defaults)
        let baseline = Set(defaults.dictionaryRepresentation().keys)
        let identifier = "001234.abcdef.5678"

        store.savePendingVehicleIDs([VehicleID()], for: identifier)

        let added = Set(defaults.dictionaryRepresentation().keys).subtracting(baseline)
        XCTAssertEqual(added.count, 1)
        for key in added { XCTAssertFalse(key.contains(identifier), key) }
    }
}
