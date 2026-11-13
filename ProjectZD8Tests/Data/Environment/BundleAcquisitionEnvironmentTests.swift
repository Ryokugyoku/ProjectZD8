import XCTest
@testable import ProjectZD8

/// `BundleAcquisitionEnvironment` を検証します。
final class BundleAcquisitionEnvironmentTests: XCTestCase {
    private func makeDefaults() throws -> UserDefaults {
        let name = "test.environment.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    /// 責務: インストールIDが初回生成され、以後も同じ値が返ることを確認します。
    func testInstallationIDIsGeneratedOnceAndPersisted() throws {
        let defaults = try makeDefaults()
        let first = BundleAcquisitionEnvironment(defaults: defaults, modelIdentifier: "Mac15,6").environment().deviceID
        let second = BundleAcquisitionEnvironment(defaults: defaults, modelIdentifier: "Mac15,6").environment().deviceID
        XCTAssertNotNil(UUID(uuidString: first))
        XCTAssertEqual(first, second)
        let other = BundleAcquisitionEnvironment(defaults: try makeDefaults(), modelIdentifier: "Mac15,6").environment().deviceID
        XCTAssertNotEqual(first, other)
    }

    /// 責務: 版情報がバンドルから読まれ、端末名がユーザー設定名ではなく機種識別子になることを確認します。
    func testReadsBundleVersionAndUsesModelIdentifier() throws {
        let environment = BundleAcquisitionEnvironment(bundle: .main, defaults: try makeDefaults(), modelIdentifier: "Mac15,6").environment()
        XCTAssertEqual(environment.appVersion, Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? BundleAcquisitionEnvironment.unknownVersion)
        XCTAssertEqual(environment.appBuild, Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? BundleAcquisitionEnvironment.unknownVersion)
        XCTAssertEqual(environment.deviceName, "Mac15,6")
        #if os(macOS)
        XCTAssertNotEqual(environment.deviceName, Host.current().localizedName)
        XCTAssertEqual(environment.platform, .mac)
        #endif
    }

    /// 責務: 実機の機種識別子が空でないことを確認します。
    func testCurrentModelIdentifierIsNotEmpty() {
        XCTAssertFalse(BundleAcquisitionEnvironment.currentModelIdentifier().isEmpty)
    }
}
