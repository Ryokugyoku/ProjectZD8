import CryptoKit
import Foundation

/// iCloud Key-Value Storeでアカウント別セッション失効世代を同期します。
@MainActor
final class UbiquitousKeyValueStoreAccountSessionRevocationStore: AccountSessionRevocationPort {
    /// 現在端末が受理済みの失効世代を保持するローカル保存先です。
    private let defaults: UserDefaults

    /// 端末間で最新の失効世代を共有するiCloud保存先です。
    private let ubiquitousStore: any UbiquitousKeyValueStorePort

    /// iCloud外部変更を配信する通知中心です。
    private let notificationCenter: NotificationCenter

    /// 現在登録中のiCloud外部変更購読です。
    private var observer: NSObjectProtocol?

    /// 現在監視中のアカウント固有失効キーです。
    private var observedRevocationKey: String?

    /// 現在監視中のアカウント固有ローカル基準キーです。
    private var observedBaselineKey: String?

    /// 現在の監視期間ですでに通知した失効世代です。
    private var deliveredMarker: Data?

    /// 未受理の失効世代をApplicationへ返す処理です。
    private var receiveRevocation: (() -> Void)?

    /// ローカル基準、iCloud同期、通知中心を注入します。
    ///
    /// 責務: セッション失効世代の端末内基準と端末間同期に使うFoundation境界を固定します。
    /// - Parameters:
    ///   - defaults: 端末が受理済みの世代を保持するローカル保存先。
    ///   - ubiquitousStore: 最新失効世代を共有するiCloud保存先。
    ///   - notificationCenter: iCloud外部変更を受け取る通知中心。
    init(
        defaults: UserDefaults = .standard,
        ubiquitousStore: any UbiquitousKeyValueStorePort = NSUbiquitousKeyValueStore.default,
        notificationCenter: NotificationCenter = .default
    ) {
        self.defaults = defaults
        self.ubiquitousStore = ubiquitousStore
        self.notificationCenter = notificationCenter
    }

    /// 新規ログイン時点のiCloud失効世代を端末内基準へ保存します。
    ///
    /// 責務: 1件の新規セッションへ現在の失効世代を受理済み基準として割り当てます。
    /// - Parameter userIdentifier: Appleがこのアプリへ割り当てたユーザー識別子。
    func registerCurrentSession(for userIdentifier: String) {
        ubiquitousStore.synchronize()
        let marker = ubiquitousStore.data(forKey: revocationKey(for: userIdentifier))
        let key = baselineKey(for: userIdentifier)
        if let marker {
            defaults.set(marker, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    /// 推測不能な新規世代をアカウント固有iCloudキーへ保存します。
    ///
    /// 責務: 1件のアカウント失効要求を新しいUUID世代として同期保存へ発行します。
    /// - Parameter userIdentifier: Appleがこのアプリへ割り当てたユーザー識別子。
    func publishRevocation(for userIdentifier: String) {
        let marker = Data(UUID().uuidString.utf8)
        ubiquitousStore.setData(marker, forKey: revocationKey(for: userIdentifier))
        ubiquitousStore.synchronize()
    }

    /// 指定アカウントの未受理失効世代を起動時確認と外部変更通知から監視します。
    ///
    /// 責務: 1件のアカウント失効キーについて端末内基準と異なる世代だけを通知します。
    /// - Parameters:
    ///   - userIdentifier: Appleがこのアプリへ割り当てたユーザー識別子。
    ///   - receive: 未受理の失効世代を検出したときに実行する処理。
    func startObserving(
        for userIdentifier: String,
        receive: @escaping () -> Void
    ) {
        stopObserving()
        observedRevocationKey = revocationKey(for: userIdentifier)
        observedBaselineKey = baselineKey(for: userIdentifier)
        receiveRevocation = receive
        observer = notificationCenter.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: ubiquitousStore,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                self?.receiveExternalChange(notification)
            }
        }
        ubiquitousStore.synchronize()
        deliverRevocationIfNeeded()
    }

    /// 現在のiCloud失効通知購読と監視情報を破棄します。
    ///
    /// 責務: 1件のセッション失効監視を再利用可能な未購読状態へ戻します。
    func stopObserving() {
        if let observer {
            notificationCenter.removeObserver(observer)
        }
        observer = nil
        observedRevocationKey = nil
        observedBaselineKey = nil
        deliveredMarker = nil
        receiveRevocation = nil
    }

    /// iCloud外部変更に監視対象の失効キーが含まれる場合だけ世代差を確認します。
    ///
    /// 責務: 1件の外部変更通知を現在監視中のアカウント失効キーへ絞り込みます。
    /// - Parameter notification: iCloud Key-Value Storeが発行した外部変更通知。
    private func receiveExternalChange(_ notification: Notification) {
        guard
            let observedRevocationKey,
            let changedKeys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey]
                as? [String],
            changedKeys.contains(observedRevocationKey)
        else { return }
        deliverRevocationIfNeeded()
    }

    /// iCloudの最新世代が端末内基準と異なる場合だけ1回通知します。
    ///
    /// 責務: 最新失効世代と受理済み基準の差を重複しない失効通知へ変換します。
    private func deliverRevocationIfNeeded() {
        guard
            let observedRevocationKey,
            let observedBaselineKey,
            let marker = ubiquitousStore.data(forKey: observedRevocationKey),
            marker != defaults.data(forKey: observedBaselineKey),
            marker != deliveredMarker
        else { return }
        deliveredMarker = marker
        receiveRevocation?()
    }

    /// Appleユーザー識別子を直接含まないiCloud失効キーへ変換します。
    ///
    /// 責務: 1件のAppleユーザー識別子を不可逆なセッション失効キーへ変換します。
    /// - Parameter userIdentifier: Appleがこのアプリへ割り当てたユーザー識別子。
    /// - Returns: スキーマ世代とSHA-256フィンガープリントを含む失効キー。
    private func revocationKey(for userIdentifier: String) -> String {
        "authentication.revocation.v1.\(fingerprint(for: userIdentifier))"
    }

    /// Appleユーザー識別子を直接含まない端末内基準キーへ変換します。
    ///
    /// 責務: 1件のAppleユーザー識別子を不可逆な受理済み世代キーへ変換します。
    /// - Parameter userIdentifier: Appleがこのアプリへ割り当てたユーザー識別子。
    /// - Returns: スキーマ世代とSHA-256フィンガープリントを含むローカル基準キー。
    private func baselineKey(for userIdentifier: String) -> String {
        "authentication.revocation.baseline.v1.\(fingerprint(for: userIdentifier))"
    }

    /// Appleユーザー識別子のSHA-256フィンガープリントを生成します。
    ///
    /// 責務: 1件のユーザー識別子を固定長の不可逆16進文字列へ変換します。
    /// - Parameter userIdentifier: フィンガープリント化するAppleユーザー識別子。
    /// - Returns: 小文字16進表現のSHA-256値。
    private func fingerprint(for userIdentifier: String) -> String {
        SHA256.hash(data: Data(userIdentifier.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
