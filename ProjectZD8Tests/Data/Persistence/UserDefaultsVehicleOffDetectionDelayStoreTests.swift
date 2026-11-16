import Foundation
import XCTest
@testable import ProjectZD8

/// `UserDefaultsVehicleOffDetectionDelayStore` の既定値・保存の往復・不正な保存値の扱い・保存先の分離を検証します。
///
/// 仕様: 未保存は既定の30秒。Int でない値と選択肢にない値は既定の30秒として読みます。
@MainActor
final class UserDefaultsVehicleOffDetectionDelayStoreTests: XCTestCase {
    /// このテストが作った UserDefaults スイート名です。終了時に消します。
    private var suiteNames: [String] = []
    /// 検証に使う保存キーです。
    private let key = "test.vehicleOffDetectionDelaySeconds"

    /// テストで作ったスイートを消します。
    ///
    /// 責務: 他のテストや実環境へ設定を残さないよう、作ったスイートの永続領域を削除します。
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
        let name = "UserDefaultsVehicleOffDetectionDelayStoreTests.\(UUID().uuidString)"
        suiteNames.append(name)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// 未保存時は既定の30秒です。
    ///
    /// 責務: 空のスイートで `load()` が30秒を返すことを確認します。
    func testLoadIsDefaultWhenUnset() throws {
        let store = UserDefaultsVehicleOffDetectionDelayStore(defaults: try makeSuite(), key: key)

        XCTAssertEqual(store.load(), .seconds30)
    }

    /// 保存した値が読め、同じスイートの別インスタンスからも同じ値が読めます。
    ///
    /// 責務: 4つの選択肢それぞれで保存の往復を確認します。
    func testSavedValueRoundTripsForEveryChoice() throws {
        let defaults = try makeSuite()
        let store = UserDefaultsVehicleOffDetectionDelayStore(defaults: defaults, key: key)

        for delay in VehicleOffDetectionDelay.allCases {
            store.save(delay)

            XCTAssertEqual(store.load(), delay)
            XCTAssertEqual(UserDefaultsVehicleOffDetectionDelayStore(defaults: defaults, key: key).load(), delay)
        }
    }

    /// 保存し直すと最後の値になります。
    ///
    /// 責務: 上書き保存が読み出しへ反映されることを確認します。
    func testLastSaveWins() throws {
        let store = UserDefaultsVehicleOffDetectionDelayStore(defaults: try makeSuite(), key: key)

        store.save(.seconds180)
        store.save(.seconds10)

        XCTAssertEqual(store.load(), .seconds10)
    }

    /// Int でない値(文字列・データ)が入っていたら既定の30秒です。
    ///
    /// 責務: 型の違う保存値を既定へ落とすことを確認します。
    func testNonIntegerValueFallsBackToDefault() throws {
        let defaults = try makeSuite()
        let store = UserDefaultsVehicleOffDetectionDelayStore(defaults: defaults, key: key)

        defaults.set("10", forKey: key)
        XCTAssertEqual(store.load(), .seconds30)
        defaults.set(Data([1, 2]), forKey: key)
        XCTAssertEqual(store.load(), .seconds30)
    }

    /// 選択肢にない秒数(45・0・負数)が入っていたら既定の30秒で、選択肢の値をそのまま返しません。
    ///
    /// 責務: 範囲外の保存値を既定へ落とすことを確認します。
    func testOutOfChoiceValueFallsBackToDefault() throws {
        let defaults = try makeSuite()
        let store = UserDefaultsVehicleOffDetectionDelayStore(defaults: defaults, key: key)

        for invalid in [45, 0, -10, 181] {
            defaults.set(invalid, forKey: key)

            XCTAssertEqual(store.load(), .seconds30, "\(invalid)")
        }
    }

    /// 保存先のキーごとに値が分かれます。
    ///
    /// 責務: 別のキーのストアへ値が漏れないことを確認します。
    func testDifferentKeysAreIsolated() throws {
        let defaults = try makeSuite()
        let first = UserDefaultsVehicleOffDetectionDelayStore(defaults: defaults, key: key)
        let second = UserDefaultsVehicleOffDetectionDelayStore(defaults: defaults, key: key + ".other")

        first.save(.seconds180)

        XCTAssertEqual(second.load(), .seconds30)
    }

    /// 既定のキーで保存した値を、同じスイートの既定のキーのストアが読めます。
    ///
    /// 責務: キー省略時の保存と読み出しが対応することを確認します。
    func testDefaultKeyRoundTrips() throws {
        let defaults = try makeSuite()

        UserDefaultsVehicleOffDetectionDelayStore(defaults: defaults).save(.seconds60)

        XCTAssertEqual(UserDefaultsVehicleOffDetectionDelayStore(defaults: defaults).load(), .seconds60)
    }
}
