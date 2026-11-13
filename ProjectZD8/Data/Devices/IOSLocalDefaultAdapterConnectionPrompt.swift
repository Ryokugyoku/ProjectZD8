#if os(iOS)
import Foundation
import UserNotifications

/// 既定BLE到来をユーザー操作可能なiOSローカル通知として提示します。
@MainActor
final class IOSLocalDefaultAdapterConnectionPrompt: NSObject,
    DefaultAdapterConnectionPrompting,
    UNUserNotificationCenterDelegate {
    /// 接続確認通知のカテゴリ識別子です。
    private static let categoryIdentifier = "DEFAULT_ADAPTER_CONNECTION"

    /// 前面起動して接続する操作の識別子です。
    private static let connectActionIdentifier = "OPEN_AND_CONNECT"

    /// 通知Payload内の物理終端フィールドです。
    private enum PayloadField {
        /// 物理通信方式のフィールド名です。
        static let transport = "transport"

        /// システム識別子のフィールド名です。
        static let systemIdentifier = "systemIdentifier"

        /// 表示名のフィールド名です。
        static let displayName = "displayName"
    }

    /// 通知の登録、配信、応答を担当するシステム境界です。
    private let center: UNUserNotificationCenter

    /// 接続開始を了承した終端の通知先です。
    private var acceptance: (@MainActor (OBDConnectionEndpoint) -> Void)?

    /// 通知応答が準備より先に届いた場合の一時終端です。
    private var pendingAcceptedEndpoint: OBDConnectionEndpoint?

    /// 標準通知センターへカテゴリとDelegateを起動完了前に登録します。
    ///
    /// 責務: 既定BLE接続確認通知の操作受付をアプリ起動ライフサイクルへ登録します。
    override init() {
        center = .current()
        super.init()
        center.delegate = self
        registerCategory()
    }

    /// 接続確認通知の了承通知先を登録して通知許可を確認します。
    ///
    /// 責務: 通知応答先とiOS通知許可を接続確認提示の準備状態へ変換します。
    /// - Parameter acceptance: ユーザーが接続を了承した終端の通知先。
    /// - Returns: Alert通知が許可済みまたは今回許可された場合は `true`。
    /// - Side Effects: 未決定の場合はiOSの通知許可ダイアログを表示します。
    func prepare(
        acceptance: @escaping @MainActor (OBDConnectionEndpoint) -> Void
    ) async -> Bool {
        self.acceptance = acceptance
        if let pendingAcceptedEndpoint {
            self.pendingAcceptedEndpoint = nil
            acceptance(pendingAcceptedEndpoint)
        }

        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) == true
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    /// 既定BLEを開いて接続するか確認する通知を直ちに配信します。
    ///
    /// 責務: 1件のBLE終端を前面起動操作付きローカル通知へ符号化します。
    /// - Parameter endpoint: ユーザー了承後に接続するBLE終端。
    /// - Side Effects: 同じ既定接続通知を置き換えてiOSへ配信要求します。
    func present(endpoint: OBDConnectionEndpoint) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "default-adapter-arrival-title")
        content.body = String(
            format: String(localized: "default-adapter-arrival-body"),
            locale: .current,
            endpoint.displayName
        )
        content.sound = .default
        content.categoryIdentifier = Self.categoryIdentifier
        content.userInfo = [
            PayloadField.transport: endpoint.transport.rawValue,
            PayloadField.systemIdentifier: endpoint.systemIdentifier,
            PayloadField.displayName: endpoint.displayName
        ]
        center.removePendingNotificationRequests(withIdentifiers: [Self.categoryIdentifier])
        center.add(
            UNNotificationRequest(
                identifier: Self.categoryIdentifier,
                content: content,
                trigger: nil
            )
        )
    }

    /// 前面表示中にも接続確認をバナーとサウンドで提示します。
    ///
    /// 責務: 前面受信した既定BLE通知の表示方法をバナーとサウンドへ固定します。
    /// - Parameters:
    ///   - center: 通知を配信したシステム通知センター。
    ///   - notification: 前面受信した接続確認通知。
    ///   - completionHandler: 選択した表示方法の通知先。
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// 通知本文または「開いて接続」の選択を承認済み接続要求へ変換します。
    ///
    /// 責務: 1件のユーザー通知応答から前面起動を伴う接続了承だけを取り出します。
    /// - Parameters:
    ///   - center: 応答を配信したシステム通知センター。
    ///   - response: ユーザーが選択した通知操作。
    ///   - completionHandler: 応答処理完了の通知先。
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let isAccepted = response.actionIdentifier == Self.connectActionIdentifier
            || response.actionIdentifier == UNNotificationDefaultActionIdentifier
        guard isAccepted,
              let endpoint = Self.endpoint(from: response.notification.request.content.userInfo) else {
            completionHandler()
            return
        }
        Task { @MainActor [weak self] in
            self?.deliverAcceptance(endpoint)
            completionHandler()
        }
    }

    /// 接続確認通知の操作カテゴリをiOSへ登録します。
    ///
    /// 責務: 前面起動する接続操作と何もしない操作を1件の通知カテゴリへ定義します。
    private func registerCategory() {
        let connect = UNNotificationAction(
            identifier: Self.connectActionIdentifier,
            title: String(localized: "default-adapter-arrival-connect-action"),
            options: [.foreground]
        )
        let decline = UNNotificationAction(
            identifier: "NOT_NOW",
            title: String(localized: "default-adapter-arrival-decline-action"),
            options: []
        )
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Self.categoryIdentifier,
                actions: [connect, decline],
                intentIdentifiers: [],
                options: []
            )
        ])
    }

    /// 通知Payloadを検証済みBLE接続終端へ復元します。
    ///
    /// 責務: 1件の通知辞書から必要フィールドが揃ったBLE終端だけを復元します。
    /// - Parameter userInfo: 接続確認通知に保存されたPayload。
    /// - Returns: 復元できたBLE終端。不完全またはBLE以外の場合は `nil`。
    nonisolated private static func endpoint(
        from userInfo: [AnyHashable: Any]
    ) -> OBDConnectionEndpoint? {
        guard let rawTransport = userInfo[PayloadField.transport] as? String,
              let transport = OBDConnectionEndpoint.Transport(rawValue: rawTransport),
              transport == .bluetoothLowEnergy,
              let systemIdentifier = userInfo[PayloadField.systemIdentifier] as? String,
              UUID(uuidString: systemIdentifier) != nil,
              let displayName = userInfo[PayloadField.displayName] as? String,
              !displayName.isEmpty else {
            return nil
        }
        return OBDConnectionEndpoint(
            transport: transport,
            systemIdentifier: systemIdentifier,
            displayName: displayName
        )
    }

    /// 承認済み終端を登録済み通知先または準備前バッファーへ渡します。
    ///
    /// 責務: 1件の接続了承を失わずApplication通知先へ引き渡します。
    /// - Parameter endpoint: 通知から復元したBLE接続終端。
    private func deliverAcceptance(_ endpoint: OBDConnectionEndpoint) {
        if let acceptance {
            acceptance(endpoint)
        } else {
            pendingAcceptedEndpoint = endpoint
        }
    }
}
#endif
