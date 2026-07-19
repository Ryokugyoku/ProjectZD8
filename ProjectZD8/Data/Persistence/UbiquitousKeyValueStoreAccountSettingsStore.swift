import CryptoKit
import Foundation

/// iCloud同期と端末ローカル保持を組み合わせてアカウント設定を保存します。
@MainActor
final class UbiquitousKeyValueStoreAccountSettingsStore: AccountSettingsStorePort {
    /// iCloudが利用できない場合も次回起動へ値を残すローカル保存先です。
    private let defaults: UserDefaults

    /// Appleアカウント間で軽量設定を同期する保存先です。
    private let ubiquitousStore: any UbiquitousKeyValueStorePort

    /// iCloudから届く外部変更を購読する通知中心です。
    private let notificationCenter: NotificationCenter

    /// 現在購読中のiCloud変更通知です。
    private var observer: NSObjectProtocol?

    /// 現在購読中のアカウント設定キーです。
    private var observedKey: String?

    /// 有効な外部変更をApplicationへ返す処理です。
    private var receiveExternalSettings: ((AccountSettings) -> Void)?

    /// ローカル保存、iCloud保存、通知中心を注入して生成します。
    ///
    /// 責務: アカウント設定のローカル保持とiCloud同期に使う3件のFoundation境界を固定します。
    /// - Parameters:
    ///   - defaults: オフライン再起動用のローカル保存先。
    ///   - ubiquitousStore: 端末間同期用のiCloud Key-Value Store。
    ///   - notificationCenter: iCloud外部変更を通知する中心。
    init(
        defaults: UserDefaults = .standard,
        ubiquitousStore: any UbiquitousKeyValueStorePort = NSUbiquitousKeyValueStore.default,
        notificationCenter: NotificationCenter = .default
    ) {
        self.defaults = defaults
        self.ubiquitousStore = ubiquitousStore
        self.notificationCenter = notificationCenter
    }

    /// 指定アカウントの同期値またはローカル値を読み込みます。
    ///
    /// 責務: 1件のアカウントキーについてiCloud値を優先しローカル値へフォールバックします。
    /// - Parameter accountIdentifier: Appleがアプリへ割り当てた空でないユーザー識別子。
    /// - Returns: 復元できた設定。未保存または不完全な場合は `nil`。
    func load(for accountIdentifier: String) -> AccountSettings? {
        let key = settingsKey(for: accountIdentifier)
        ubiquitousStore.synchronize()

        if let synchronized = decode(ubiquitousStore.data(forKey: key)) {
            persistLocally(synchronized, forKey: key)
            return synchronized
        }
        return decode(defaults.data(forKey: key))
    }

    /// 指定アカウントの設定をローカルとiCloudへ保存します。
    ///
    /// 責務: 1件のアカウント設定を同じ符号化値でローカル保持とiCloud同期へ反映します。
    /// - Parameters:
    ///   - settings: Connectionを含まない保存対象設定。
    ///   - accountIdentifier: Appleがアプリへ割り当てた空でないユーザー識別子。
    func save(_ settings: AccountSettings, for accountIdentifier: String) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        let key = settingsKey(for: accountIdentifier)
        defaults.set(data, forKey: key)
        ubiquitousStore.setData(data, forKey: key)
        ubiquitousStore.synchronize()
    }

    /// 指定アカウントのローカル設定とiCloud共有設定を削除します。
    ///
    /// 責務: 1件のアカウント設定キーを両方の保存先から除去して同期を要求します。
    /// - Parameter accountIdentifier: Appleがアプリへ割り当てた空でないユーザー識別子。
    func remove(for accountIdentifier: String) {
        let key = settingsKey(for: accountIdentifier)
        if observedKey == key {
            stopObserving()
        }
        defaults.removeObject(forKey: key)
        ubiquitousStore.removeObject(forKey: key)
        ubiquitousStore.synchronize()
    }

    /// 指定アカウントのiCloud外部変更を購読します。
    ///
    /// 責務: 1件のアカウント設定キーだけをiCloud変更通知から選別して購読します。
    /// - Parameters:
    ///   - accountIdentifier: Appleがアプリへ割り当てた空でないユーザー識別子。
    ///   - receive: 有効な同期設定を受け取る処理。
    func startObserving(
        for accountIdentifier: String,
        receive: @escaping (AccountSettings) -> Void
    ) {
        stopObserving()
        observedKey = settingsKey(for: accountIdentifier)
        receiveExternalSettings = receive
        observer = notificationCenter.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: ubiquitousStore,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                self?.receiveExternalChange(notification)
            }
        }
    }

    /// 現在のiCloud外部変更購読を終了します。
    ///
    /// 責務: 登録済みの1件の通知購読とアカウント固有コールバックを破棄します。
    func stopObserving() {
        if let observer {
            notificationCenter.removeObserver(observer)
        }
        observer = nil
        observedKey = nil
        receiveExternalSettings = nil
    }

    /// iCloud変更通知から現在のアカウント設定だけを反映します。
    ///
    /// 責務: 外部変更キーを現在のアカウントへ照合し有効な設定1件を通知します。
    /// - Parameter notification: iCloud Key-Value Storeが発行した外部変更通知。
    private func receiveExternalChange(_ notification: Notification) {
        guard
            let observedKey,
            let changedKeys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey]
                as? [String],
            changedKeys.contains(observedKey),
            let settings = decode(ubiquitousStore.data(forKey: observedKey))
        else { return }

        persistLocally(settings, forKey: observedKey)
        receiveExternalSettings?(settings)
    }

    /// Appleユーザー識別子を直接保存しないアカウント固有キーへ変換します。
    ///
    /// 責務: 1件のAppleユーザー識別子をSHA-256名前空間付き設定キーへ変換します。
    /// - Parameter accountIdentifier: Appleがアプリへ割り当てたユーザー識別子。
    /// - Returns: スキーマ世代と不可逆フィンガープリントを含む保存キー。
    private func settingsKey(for accountIdentifier: String) -> String {
        let digest = SHA256.hash(data: Data(accountIdentifier.utf8))
        let fingerprint = digest.map { String(format: "%02x", $0) }.joined()
        return "settings.account.v1.\(fingerprint)"
    }

    /// 任意の保存データを完全なアカウント設定へ復元します。
    ///
    /// 責務: 1件のJSONデータを検証可能なアカウント設定へ復号します。
    /// - Parameter data: iCloudまたはローカル保存先から読み込んだデータ。
    /// - Returns: 復号できた設定。不完全または未保存の場合は `nil`。
    private func decode(_ data: Data?) -> AccountSettings? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(AccountSettings.self, from: data)
    }

    /// 同期から得た有効な設定をローカル保存へ反映します。
    ///
    /// 責務: 1件の有効なアカウント設定をオフライン再起動用データとして保存します。
    /// - Parameters:
    ///   - settings: iCloudから復元した有効な設定。
    ///   - key: アカウント固有の保存キー。
    private func persistLocally(_ settings: AccountSettings, forKey key: String) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}
