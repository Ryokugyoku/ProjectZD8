#if os(iOS)
import Foundation
import UserNotifications

/// 既定BLEアダプターの出現を、ユーザーが応じられるiOSローカル通知として提示します。
@MainActor
final class IOSAdapterArrivalNotifier: NSObject, UNUserNotificationCenterDelegate {
    /// 通知カテゴリと通知リクエストの識別子です。
    nonisolated private static let categoryIdentifier = "DEFAULT_ADAPTER_CONNECTION"
    /// 前面起動して接続する操作の識別子です。
    nonisolated private static let connectActionIdentifier = "OPEN_AND_CONNECT"
    /// 何もしない操作の識別子です。
    nonisolated private static let declineActionIdentifier = "NOT_NOW"

    /// 通知Payload内のフィールド名です。
    nonisolated private enum PayloadField {
        static let systemIdentifier = "systemIdentifier"
        static let displayName = "displayName"
    }

    /// 通知の登録・配信・応答を担当するシステム境界です。
    private let center: UNUserNotificationCenter
    /// ユーザーが接続を了承したアダプターの通知先です。
    private var acceptance: (@MainActor (AdapterDescriptor) -> Void)?
    /// 通知応答が通知先の登録より先に届いた場合の保留アダプターです。
    private var pendingAcceptedAdapter: AdapterDescriptor?

    /// 標準通知センターへカテゴリとDelegateを登録して生成します。起動完了前に生成してください。
    ///
    /// 責務: 接続確認通知の操作受付をアプリ起動のライフサイクルへ登録します。
    override init() {
        center = .current()
        super.init()
        center.delegate = self
        registerCategory()
    }

    /// 責務: 了承の通知先を登録し、通知の許可状態を確認(未決定なら要求)して提示可否を返します。
    /// - Returns: 通知が許可済みまたは今回許可された場合は `true`。
    /// - Side Effects: 未決定の場合はiOSの通知許可ダイアログを表示します。
    func prepare(acceptance: @escaping @MainActor (AdapterDescriptor) -> Void) async -> Bool {
        self.acceptance = acceptance
        if let pendingAcceptedAdapter {
            self.pendingAcceptedAdapter = nil
            acceptance(pendingAcceptedAdapter)
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

    /// 責務: 1件のBLEアダプターを前面起動操作付きのローカル通知として直ちに配信します。同じ通知は置き換えます。
    func present(_ adapter: AdapterDescriptor) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "deviceConnection.arrival.title")
        content.body = String(
            format: String(localized: "deviceConnection.arrival.body"),
            locale: .current,
            adapter.displayName
        )
        content.sound = .default
        content.categoryIdentifier = Self.categoryIdentifier
        content.userInfo = [
            PayloadField.systemIdentifier: adapter.systemIdentifier,
            PayloadField.displayName: adapter.displayName
        ]
        center.removePendingNotificationRequests(withIdentifiers: [Self.categoryIdentifier])
        center.add(UNNotificationRequest(identifier: Self.categoryIdentifier, content: content, trigger: nil))
    }

    /// 責務: 前面表示中でもバナーとサウンドで提示します。
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// 責務: 本文タップまたは「開いて接続」の応答だけを、接続了承としてアプリへ渡します。
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let isAccepted = response.actionIdentifier == Self.connectActionIdentifier
            || response.actionIdentifier == UNNotificationDefaultActionIdentifier
        guard isAccepted,
              let adapter = Self.adapter(from: response.notification.request.content.userInfo) else {
            completionHandler()
            return
        }
        Task { @MainActor [weak self] in
            self?.deliverAcceptance(adapter)
            completionHandler()
        }
    }

    /// 責務: 「開いて接続」と「今はしない」の通知操作をカテゴリとして登録します。
    private func registerCategory() {
        let connect = UNNotificationAction(
            identifier: Self.connectActionIdentifier,
            title: String(localized: "deviceConnection.arrival.connectAction"),
            options: [.foreground]
        )
        let decline = UNNotificationAction(
            identifier: Self.declineActionIdentifier,
            title: String(localized: "deviceConnection.arrival.declineAction"),
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

    /// 責務: 通知Payloadから、必要項目が揃ったBLEアダプターだけを復元します。
    nonisolated private static func adapter(from userInfo: [AnyHashable: Any]) -> AdapterDescriptor? {
        guard let systemIdentifier = userInfo[PayloadField.systemIdentifier] as? String,
              UUID(uuidString: systemIdentifier) != nil,
              let displayName = userInfo[PayloadField.displayName] as? String,
              !displayName.isEmpty else {
            return nil
        }
        return AdapterDescriptor(
            transport: .bluetoothLowEnergy,
            systemIdentifier: systemIdentifier,
            displayName: displayName
        )
    }

    /// 責務: 了承を失わないよう、登録済みの通知先、または準備前の保留へ渡します。
    private func deliverAcceptance(_ adapter: AdapterDescriptor) {
        if let acceptance {
            acceptance(adapter)
        } else {
            pendingAcceptedAdapter = adapter
        }
    }
}
#endif
