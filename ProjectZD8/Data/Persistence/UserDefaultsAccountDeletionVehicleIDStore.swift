import CryptoKit
import Foundation

/// `UserDefaults` へ、アカウント削除の再試行に備えた車両IDの控えを端末ローカルで保持します。
@MainActor
final class UserDefaultsAccountDeletionVehicleIDStore: AccountDeletionVehicleIDStorePort {
    /// 控えを保存する `UserDefaults` です。
    private let defaults: UserDefaults

    /// 保存先を注入してストアを生成します。
    ///
    /// 責務: 控えの保存先を1件の `UserDefaults` へ固定します。
    /// - Parameter defaults: 控えを保存する `UserDefaults`。
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 控えた車両IDを読み込みます。
    ///
    /// 責務: 保存済みのUUID文字列を車両IDへ復元します。未保存・復元できない値は無視します。
    /// - Parameter accountIdentifier: 削除対象のAppleアカウント識別子。
    /// - Returns: 控えた車両ID群。
    func pendingVehicleIDs(for accountIdentifier: String) -> [VehicleID] {
        guard let strings = defaults.stringArray(forKey: key(for: accountIdentifier)) else { return [] }
        return strings.compactMap { UUID(uuidString: $0).map(VehicleID.init(rawValue:)) }
    }

    /// 車両IDを控えとして保存します。
    ///
    /// 責務: 既存の控えを置き換えて保存します。空配列なら控えを消します。
    /// - Parameters:
    ///   - vehicleIDs: 控える車両ID群。
    ///   - accountIdentifier: 削除対象のAppleアカウント識別子。
    func savePendingVehicleIDs(_ vehicleIDs: [VehicleID], for accountIdentifier: String) {
        guard !vehicleIDs.isEmpty else {
            clearPendingVehicleIDs(for: accountIdentifier)
            return
        }
        defaults.set(vehicleIDs.map { $0.rawValue.uuidString }, forKey: key(for: accountIdentifier))
    }

    /// 控えを消します。
    ///
    /// 責務: 1件のアカウントの控えを削除します。
    /// - Parameter accountIdentifier: 削除が成功したAppleアカウント識別子。
    func clearPendingVehicleIDs(for accountIdentifier: String) {
        defaults.removeObject(forKey: key(for: accountIdentifier))
    }

    /// 保存キーを生成します。
    ///
    /// 責務: Apple識別子を平文で保存せず、SHA-256の指紋を含む世代付きキーへ変換します。
    /// - Parameter accountIdentifier: Appleアカウントのアプリ固有識別子。
    /// - Returns: アカウント別の保存キー。
    private func key(for accountIdentifier: String) -> String {
        let fingerprint = SHA256.hash(data: Data(accountIdentifier.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return "account.deletion.pendingVehicleIDs.v1.\(fingerprint)"
    }
}
