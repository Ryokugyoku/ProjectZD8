#if os(iOS)
import Foundation
import OSLog
import UserNotifications

/// 車両検知と記録開始を `UNUserNotificationCenter` のローカル通知で知らせるiOS実装です。
///
/// 通知内容は `VehicleDetectionNotificationCatalog` が決め、この型はシステムへの登録・提示・取り下げと応答の受け取りだけを行います。
/// 通知センターの delegate は1つしか持てないため、生成時には設定しません。配線側が `activateResponseHandling()` を
/// アプリ起動完了前に1回呼んだ時だけ delegate になります(他の型を通知センターの delegate にしないこと)。
@MainActor
final class IOSVehicleDetectionNotifier: NSObject, VehicleDetectionNotificationPort, UNUserNotificationCenterDelegate {
    /// 通知の登録・配信・応答を担当するシステム境界です。
    private let center: UNUserNotificationCenter
    /// 通知内容の定義です。
    private let catalog = VehicleDetectionNotificationCatalog()
    /// 許可状態の判定方針です。
    private let authorizationPolicy = VehicleDetectionNotificationAuthorizationPolicy()
    /// 提示失敗を記録するロガーです。
    private let logger = Logger(subsystem: DiagnosticsLogSubsystem.identifier, category: "VehicleDetectionNotification")
    /// [記録開始]が選ばれたときに呼ぶ処理です。
    private var recordingStartSelected: (@MainActor () -> Void)?
    /// 準備より先に[記録開始]が選ばれていたかどうかです(通知からの起動直後)。
    private var hasPendingRecordingStartSelection = false
    /// 提示・取り下げの世代です。非同期の提示が後から来た取り下げを追い越さないために使います。
    private var requestGeneration: UInt64 = 0

    /// 通知センターを固定して生成します。
    ///
    /// 責務: 監視通知の送り先を1件の通知センターへ結び付けます。delegate は設定しません。
    /// - Parameter center: 使う通知センター。
    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        super.init()
    }

    /// 通知への応答を受け取れるよう、自分を通知センターの delegate にします。
    ///
    /// 責務: 通知の[記録開始]操作と前面表示をこの型で扱えるようにします。
    /// - Side Effects: 通知センターの delegate を置き換えます。通知から起動された応答を受けるため、起動完了前に呼ぶこと。
    func activateResponseHandling() {
        center.delegate = self
    }

    /// 通知の許可・カテゴリ・[記録開始]操作の受け口を準備します。
    ///
    /// 責務: 応答先を登録して保留中の選択を渡し、カテゴリを登録し、許可状態を確かめます。
    /// - Parameter recordingStartSelected: [記録開始]が選ばれたときに呼ぶ処理。
    /// - Returns: 提示が許可されている(今回許可された場合を含む)なら `true`。
    /// - Side Effects: 未決定の場合は通知許可ダイアログを表示します。
    func prepare(recordingStartSelected: @escaping @MainActor () -> Void) async -> Bool {
        self.recordingStartSelected = recordingStartSelected
        if hasPendingRecordingStartSelection {
            hasPendingRecordingStartSelection = false
            recordingStartSelected()
        }
        await registerCategory()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else {
            return authorizationPolicy.allowsPresentation(settings.authorizationStatus)
        }
        return (try? await center.requestAuthorization(options: [.alert, .sound])) == true
    }

    /// 「車両を検知しました」通知を提示します。提示済みの監視通知は置き換えます。
    ///
    /// 責務: 検知を[記録開始]操作付きの Time Sensitive 通知としてシステムへ渡します。
    /// - Parameter vin: 読み取ったVIN。読めなかった場合は `nil`。
    func presentVehicleDetected(vin: String?) {
        present(catalog.vehicleDetected(vin: vin))
    }

    /// 「記録を開始しました」通知を提示します。提示済みの監視通知は置き換えます。
    ///
    /// 責務: 自動記録の開始を通知としてシステムへ渡します。
    /// - Parameter vin: 読み取ったVIN。読めなかった場合は `nil`。
    func presentRecordingStarted(vin: String?) {
        present(catalog.recordingStarted(vin: vin))
    }

    /// 提示中の監視通知を取り下げます。
    ///
    /// 責務: 監視通知を配信済み・保留中の両方から取り除き、進行中の提示も取り消します。
    func dismiss() {
        requestGeneration &+= 1
        center.removeDeliveredNotifications(withIdentifiers: VehicleDetectionNotificationCatalog.allIdentifiers)
        center.removePendingNotificationRequests(withIdentifiers: VehicleDetectionNotificationCatalog.allIdentifiers)
    }

    /// 前面表示中にも監視通知をバナーとサウンドで提示します。
    ///
    /// 責務: 前面受信した通知の表示方法をバナー・一覧・サウンドへ固定します。
    /// - Parameters:
    ///   - center: 通知を配信したシステム通知センター。
    ///   - notification: 前面受信した通知。
    ///   - completionHandler: 選択した表示方法の通知先。
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    /// 通知への応答のうち[記録開始]の選択だけを登録済みの処理へ渡します。
    ///
    /// 責務: 1件の通知応答を判定し、[記録開始]ならメインアクターで応答先へ届けます。
    /// - Parameters:
    ///   - center: 応答を配信したシステム通知センター。
    ///   - response: ユーザーが選んだ通知操作。
    ///   - completionHandler: 応答処理完了の通知先。
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let isSelected = VehicleDetectionNotificationCatalog().isRecordingStartSelection(
            actionIdentifier: response.actionIdentifier,
            categoryIdentifier: response.notification.request.content.categoryIdentifier
        )
        if isSelected {
            Task { @MainActor [weak self] in
                self?.deliverRecordingStartSelection()
            }
        }
        completionHandler()
    }

    /// [記録開始]の選択を応答先へ届けます。
    ///
    /// 責務: 応答先が登録済みなら呼び、未登録なら準備時に届けるために保留します。
    private func deliverRecordingStartSelection() {
        if let recordingStartSelected {
            recordingStartSelected()
        } else {
            hasPendingRecordingStartSelection = true
        }
    }

    /// 監視カテゴリを既存のカテゴリと併せて登録します。
    ///
    /// 責務: 他の通知のカテゴリを消さずに、[記録開始]操作を持つカテゴリを追加・置き換えます。
    private func registerCategory() async {
        let startRecording = UNNotificationAction(
            identifier: VehicleDetectionNotificationCatalog.startRecordingActionIdentifier,
            title: String(localized: String.LocalizationValue(VehicleDetectionNotificationCatalog.startRecordingActionTitleKey)),
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: VehicleDetectionNotificationCatalog.categoryIdentifier,
            actions: [startRecording],
            intentIdentifiers: [],
            options: []
        )
        let others = await center.notificationCategories().filter { $0.identifier != category.identifier }
        center.setNotificationCategories(others.union([category]))
    }

    /// 監視通知を、許可がある場合だけ置き換え式で提示します。
    ///
    /// 責務: 許可状態を確かめ、その間に新しい提示や取り下げが無かった場合だけ他の監視通知を消して追加します。
    /// - Parameter content: 提示する通知内容。
    private func present(_ content: VehicleDetectionNotificationContent) {
        requestGeneration &+= 1
        let generation = requestGeneration
        Task { @MainActor [weak self] in
            await self?.deliver(content, generation: generation)
        }
    }

    /// 許可状態を確かめてから通知を追加します。
    ///
    /// 責務: 許可が無い・世代が古い場合は提示せず、追加失敗は記録します。
    /// - Parameters:
    ///   - content: 提示する通知内容。
    ///   - generation: 提示を要求した時点の世代。
    private func deliver(_ content: VehicleDetectionNotificationContent, generation: UInt64) async {
        let settings = await center.notificationSettings()
        guard authorizationPolicy.allowsPresentation(settings.authorizationStatus) else {
            logger.info("Vehicle detection notification skipped: not authorized")
            return
        }
        guard generation == requestGeneration else { return }
        let replaced = catalog.identifiersReplaced(by: content)
        center.removeDeliveredNotifications(withIdentifiers: replaced)
        center.removePendingNotificationRequests(withIdentifiers: replaced)
        do {
            try await center.add(UNNotificationRequest(identifier: content.identifier, content: Self.makeContent(content), trigger: nil))
        } catch {
            logger.error("Vehicle detection notification failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// 通知内容をシステムの通知内容へ変換します。
    ///
    /// 責務: 文言キーをローカライズし、カテゴリと割り込みレベルを設定します。
    /// - Parameter content: 通知内容。
    /// - Returns: システムへ渡す通知内容。
    private static func makeContent(_ content: VehicleDetectionNotificationContent) -> UNMutableNotificationContent {
        let notification = UNMutableNotificationContent()
        notification.title = String(localized: String.LocalizationValue(content.titleKey))
        let bodyFormat = String(localized: String.LocalizationValue(content.bodyKey))
        notification.body = content.bodyArguments.isEmpty
            ? bodyFormat
            : String(format: bodyFormat, locale: .current, arguments: content.bodyArguments.map { $0 as CVarArg })
        notification.sound = .default
        if let categoryIdentifier = content.categoryIdentifier {
            notification.categoryIdentifier = categoryIdentifier
        }
        switch content.interruptionLevel {
        case .active:
            notification.interruptionLevel = .active
        case .timeSensitive:
            notification.interruptionLevel = .timeSensitive
        }
        return notification
    }
}
#endif
