import Foundation
import XCTest
@testable import ProjectZD8

/// Keychain認証セッション保存の実ローカル境界を検証します。
@MainActor
final class KeychainAuthenticationSessionStoreTests: XCTestCase {
    /// Appleユーザー識別子を保存、読込、削除できることを検証します。
    ///
    /// 責務: 一意なKeychain項目で認証セッション識別子の往復と削除を確認します。
    func testSaveLoadAndRemoveUserIdentifier() throws {
        let store = makeStore()
        defer { try? store.removeUserIdentifier() }

        try store.saveUserIdentifier("keychain-user")
        XCTAssertEqual(try store.loadUserIdentifier(), "keychain-user")

        try store.removeUserIdentifier()
        XCTAssertNil(try store.loadUserIdentifier())
    }

    /// 空のAppleユーザー識別子をKeychainへ保存しないことを検証します。
    ///
    /// 責務: 不完全な認証セッション識別子がKeychain書込前に拒否されることを確認します。
    func testEmptyUserIdentifierIsRejected() {
        let store = makeStore()
        defer { try? store.removeUserIdentifier() }

        XCTAssertThrowsError(try store.saveUserIdentifier("")) { error in
            XCTAssertEqual(error as? AuthenticationSessionStoreError, .unavailable)
        }
    }

    /// 各テスト専用のKeychain保存境界を生成します。
    ///
    /// 責務: テスト間で衝突しない一意なKeychainサービス名を割り当てます。
    /// - Returns: 一意なサービス名を使用するKeychainセッションストア。
    private func makeStore() -> KeychainAuthenticationSessionStore {
        KeychainAuthenticationSessionStore(
            service: "Ryokugyoku.ProjectZD8Tests.\(UUID().uuidString)"
        )
    }
}
