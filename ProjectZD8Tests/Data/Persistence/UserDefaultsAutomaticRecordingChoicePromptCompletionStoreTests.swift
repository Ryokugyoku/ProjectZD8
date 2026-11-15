import Foundation
import XCTest
@testable import ProjectZD8

/// `UserDefaultsAutomaticRecordingChoicePromptCompletionStore` の未設定時・保存・保存先の分離を検証します。
@MainActor
final class UserDefaultsAutomaticRecordingChoicePromptCompletionStoreTests: XCTestCase {
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
        let name = "UserDefaultsAutomaticRecordingChoicePromptCompletionStoreTests.\(UUID().uuidString)"
        suiteNames.append(name)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// 未設定時は未表示です。
    ///
    /// 責務: 空のスイートで `isCompleted()` が `false` を返すことを確認します。
    func testIsNotCompletedWhenUnset() throws {
        let store = UserDefaultsAutomaticRecordingChoicePromptCompletionStore(defaults: try makeSuite())
        XCTAssertFalse(store.isCompleted())
    }

    /// 表示済みにすると、同じストアと同じスイートの別インスタンスから表示済みとして読めます。
    ///
    /// 責務: `markCompleted()` の保存が永続化先へ届くことを確認します。
    func testMarkCompletedIsPersisted() throws {
        let defaults = try makeSuite()
        let store = UserDefaultsAutomaticRecordingChoicePromptCompletionStore(defaults: defaults)

        store.markCompleted()

        XCTAssertTrue(store.isCompleted())
        XCTAssertTrue(UserDefaultsAutomaticRecordingChoicePromptCompletionStore(defaults: defaults).isCompleted())
    }

    /// 表示済みの保存は別のスイートと `UserDefaults.standard` へ影響しません。
    ///
    /// 責務: 一方のスイートで表示済みにしても、もう一方のスイートが空のままで、標準領域の既定キーの値も変わらないことを確認します。
    func testMarkCompletedDoesNotAffectOtherSuites() throws {
        let key = "deviceConnection.automaticRecordingChoicePromptCompleted"
        let standardBefore = UserDefaults.standard.object(forKey: key) as? Bool
        let written = try makeSuite()
        let other = try makeSuite()

        UserDefaultsAutomaticRecordingChoicePromptCompletionStore(defaults: written).markCompleted()

        XCTAssertFalse(UserDefaultsAutomaticRecordingChoicePromptCompletionStore(defaults: other).isCompleted())
        XCTAssertEqual(other.persistentDomain(forName: try XCTUnwrap(suiteNames.last))?.isEmpty ?? true, true)
        XCTAssertEqual(UserDefaults.standard.object(forKey: key) as? Bool, standardBefore)
    }
}
