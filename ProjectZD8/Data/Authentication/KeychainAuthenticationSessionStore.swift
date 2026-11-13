import Foundation
import Security

/// Keychainを使ってAppleユーザー識別子を端末内へ安全に保持します。
final class KeychainAuthenticationSessionStore: AuthenticationSessionStorePort {
    /// Keychain項目を所有するサービス名です。
    private let service: String

    /// Appleユーザー識別子を保持するKeychainアカウント名です。
    private let account: String

    /// Keychain項目のサービス名とアカウント名を注入します。
    ///
    /// 責務: 認証セッション識別子の保存先を1件のKeychain項目へ固定します。
    /// - Parameters:
    ///   - service: Keychain項目をアプリ単位で識別するサービス名。
    ///   - account: Appleユーザー識別子を保存する項目名。
    init(
        service: String = "Ryokugyoku.ProjectZD8.authentication",
        account: String = "apple-account-user-identifier"
    ) {
        self.service = service
        self.account = account
    }

    /// 保存済みAppleユーザー識別子をKeychainから読み込みます。
    ///
    /// 責務: 1件のKeychainデータをUTF-8の認証セッション識別子へ復元します。
    /// - Returns: 保存済み識別子。未保存の場合は `nil`。
    /// - Throws: Keychain読込または保存値の復元を完了できない場合は `AuthenticationSessionStoreError`。
    func loadUserIdentifier() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }
        guard
            status == errSecSuccess,
            let data = item as? Data,
            let userIdentifier = String(data: data, encoding: .utf8),
            !userIdentifier.isEmpty
        else {
            throw AuthenticationSessionStoreError.unavailable
        }
        return userIdentifier
    }

    /// Appleユーザー識別子をKeychainへ置き換え保存します。
    ///
    /// 責務: 1件のUTF-8認証セッション識別子を端末限定Keychain項目として保存します。
    /// - Parameter userIdentifier: Appleがこのアプリへ割り当てた空でないユーザー識別子。
    /// - Throws: 空の識別子またはKeychain書込失敗の場合は `AuthenticationSessionStoreError`。
    func saveUserIdentifier(_ userIdentifier: String) throws {
        guard
            !userIdentifier.isEmpty,
            let data = userIdentifier.data(using: .utf8)
        else {
            throw AuthenticationSessionStoreError.unavailable
        }

        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw AuthenticationSessionStoreError.unavailable
        }

        var item = baseQuery
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
            throw AuthenticationSessionStoreError.unavailable
        }
    }

    /// 保存済みAppleユーザー識別子をKeychainから削除します。
    ///
    /// 責務: 1件の認証セッションKeychain項目を存在しない状態へします。
    /// - Throws: Keychain項目を削除できない場合は `AuthenticationSessionStoreError`。
    func removeUserIdentifier() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AuthenticationSessionStoreError.unavailable
        }
    }

    /// 対象のKeychain項目を一意に識別する共通クエリです。
    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
