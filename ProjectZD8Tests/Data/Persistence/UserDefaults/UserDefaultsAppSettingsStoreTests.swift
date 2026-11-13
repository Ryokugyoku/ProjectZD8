import XCTest
@testable import ProjectZD8

/// `UserDefaultsAppSettingsStore` の既定値・保存・破損データ処理を検証します。
final class UserDefaultsAppSettingsStoreTests: XCTestCase {
    private func makeDefaults() throws -> UserDefaults {
        let name = "test.settings.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    /// 責務: 未保存ならプラットフォーム既定の保持期間を持つ既定設定を返すことを確認します。
    func testUnsavedReturnsDefaults() throws {
        let store = UserDefaultsAppSettingsStore(defaults: try makeDefaults(), defaultLocalRawRetention: .days30)
        XCTAssertEqual(store.load(), AppSettings(appearance: .system, isDemoModeEnabled: false, localRawRetention: .days30))
    }

    /// 責務: 保存した設定が別インスタンスから読めることを確認します。
    func testSaveRoundTrips() throws {
        let defaults = try makeDefaults()
        let settings = AppSettings(appearance: .dark, isDemoModeEnabled: true, localRawRetention: .unlimited)
        UserDefaultsAppSettingsStore(defaults: defaults, defaultLocalRawRetention: .days30).save(settings)
        XCTAssertEqual(UserDefaultsAppSettingsStore(defaults: defaults, defaultLocalRawRetention: .days30).load(), settings)
    }

    /// 責務: 復元できない保存データが既定設定として扱われることを確認します。
    func testUndecodableDataReturnsDefaults() throws {
        let defaults = try makeDefaults()
        defaults.set(Data("garbage".utf8), forKey: UserDefaultsAppSettingsStore.key)
        let store = UserDefaultsAppSettingsStore(defaults: defaults, defaultLocalRawRetention: .days90)
        XCTAssertEqual(store.load().localRawRetention, .days90)
    }
}
