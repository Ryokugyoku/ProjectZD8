import Foundation
import XCTest
@testable import ProjectZD8

/// `UserDefaultsAutomaticRecordingPreferenceStore` の既定値・保存・保存先の分離を検証します。
@MainActor
final class UserDefaultsAutomaticRecordingPreferenceStoreTests: XCTestCase {
    /// このテストが作った UserDefaults スイート名です。終了時に消します。
    private var suiteNames: [String] = []

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
        let name = "UserDefaultsAutomaticRecordingPreferenceStoreTests.\(UUID().uuidString)"
        suiteNames.append(name)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// 未設定時はオフです。
    ///
    /// 責務: 空のスイートで `load()` が `false` を返すことを確認します。
    func testLoadIsOffWhenUnset() throws {
        let store = UserDefaultsAutomaticRecordingPreferenceStore(defaults: try makeSuite())
        XCTAssertFalse(store.load())
    }

    /// 保存したオン・オフが読め、別インスタンスからも同じ値が読めます。
    ///
    /// 責務: オン→オフの順に保存し、それぞれ同じスイートの新しいストアでも反映されることを確認します。
    func testSavedValueIsLoaded() throws {
        let defaults = try makeSuite()
        let store = UserDefaultsAutomaticRecordingPreferenceStore(defaults: defaults)

        store.save(true)
        XCTAssertTrue(store.load())
        XCTAssertTrue(UserDefaultsAutomaticRecordingPreferenceStore(defaults: defaults).load())

        store.save(false)
        XCTAssertFalse(store.load())
        XCTAssertFalse(UserDefaultsAutomaticRecordingPreferenceStore(defaults: defaults).load())
    }

    /// 保存は別のスイートへ影響しません。
    ///
    /// 責務: 一方のスイートでオンにしても、もう一方と `UserDefaults.standard` の同じキーが変わらないことを確認します。
    func testSaveDoesNotAffectOtherSuites() throws {
        let key = "deviceConnection.automaticRecordingEnabled"
        let standardBefore = UserDefaults.standard.object(forKey: key) as? Bool
        let written = try makeSuite()
        let other = try makeSuite()

        UserDefaultsAutomaticRecordingPreferenceStore(defaults: written).save(true)

        XCTAssertFalse(UserDefaultsAutomaticRecordingPreferenceStore(defaults: other).load())
        XCTAssertNil(other.object(forKey: key))
        XCTAssertEqual(UserDefaults.standard.object(forKey: key) as? Bool, standardBefore)
    }
}
