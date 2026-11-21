import Observation

/// 設定画面の「走行ルートを記録」区画の操作を、設定の保存・位置情報の許可要求・表示内容へ変換します。
///
/// 許可は2段階で要求します。オンにした時に許可が未確定なら「使用中のみ」だけを要求し、「常に許可」の要求を保留します。
/// その後「使用中のみ」へ変わったら、保留していた「常に許可」を1回だけ要求します。
@MainActor
@Observable
final class RouteRecordingSettingsModel {
    /// 設定画面が描画する区画内容です。
    private(set) var section: RouteRecordingSettingsSection

    /// 記録設定の読み書きを行うユースケースです。
    @ObservationIgnored
    private let preference: RouteRecordingPreferenceUseCase
    /// 位置情報の許可の読取と要求の境界です。
    @ObservationIgnored
    private let authorization: any LocationAuthorizationPort
    /// 保存後の記録設定を受け取る処理です。
    @ObservationIgnored
    private let preferenceDidChange: @MainActor (Bool) -> Void
    /// 直近に受け取った許可状態です。
    @ObservationIgnored
    private var permission: LocationPermission
    /// 「使用中のみ」の許可が得られた時に「常に許可」を要求する予定なら `true`。
    @ObservationIgnored
    private var isAlwaysAuthorizationRequestPending = false

    /// ユースケースと許可の境界を注入し、保存済みの設定と現在の許可から区画内容を作ります。
    ///
    /// 責務: 保存済みの記録設定と現在の許可状態を初期の区画内容へ反映します。
    /// - Parameters:
    ///   - preference: 記録設定の読み書きを行うユースケース。
    ///   - authorization: 位置情報の許可の読取と要求の境界。
    ///   - preferenceDidChange: 保存後の記録設定を受け取る処理。
    init(
        preference: RouteRecordingPreferenceUseCase,
        authorization: any LocationAuthorizationPort,
        preferenceDidChange: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        self.preference = preference
        self.authorization = authorization
        self.preferenceDidChange = preferenceDidChange
        let permission = authorization.currentPermission
        self.permission = permission
        section = RouteRecordingSettingsSection(isEnabled: preference.load(), permission: permission)
    }

    /// 受け取った操作を保存・許可要求・表示内容へ反映します。
    ///
    /// 責務: 1件の操作をトグルの処理か許可の変化の処理へ振り分けます。
    /// - Parameter action: 設定画面または配線から通知された型付き操作。
    func send(_ action: RouteRecordingSettingsAction) {
        switch action {
        case let .toggled(isEnabled):
            toggle(isEnabled)
        case let .permissionChanged(newPermission):
            applyPermission(newPermission)
        }
    }

    /// 記録設定を保存し、必要な許可を要求して、保存し直した値を表示と通知へ反映します。
    ///
    /// 責務: 1回のトグル操作を、保存・許可要求(または保留の解除)・区画の更新・保存値の通知へ変換します。
    /// - Parameter isEnabled: 利用者が選んだ記録設定。
    private func toggle(_ isEnabled: Bool) {
        preference.save(isEnabled)
        let savedValue = preference.load()
        if savedValue {
            requestAuthorizationForEnabling()
        } else {
            isAlwaysAuthorizationRequestPending = false
        }
        section = RouteRecordingSettingsSection(isEnabled: savedValue, permission: permission)
        preferenceDidChange(savedValue)
    }

    /// 記録をオンにした時の許可要求を行います。
    ///
    /// 責務: 未確定なら「使用中のみ」を要求して「常に許可」を保留し、「使用中のみ」なら「常に許可」を要求します。
    private func requestAuthorizationForEnabling() {
        switch permission.level {
        case .notDetermined:
            isAlwaysAuthorizationRequestPending = true
            authorization.requestWhenInUseAuthorization()
        case .whenInUse:
            isAlwaysAuthorizationRequestPending = false
            authorization.requestAlwaysAuthorization()
        case .denied, .restricted, .always, .unsupportedPlatform:
            break
        }
    }

    /// 許可状態の変化を表示へ反映し、保留中の「常に許可」の要求を行います。
    ///
    /// 責務: 新しい許可状態を保持し、「使用中のみ」へ変わって保留中なら「常に許可」を1回だけ要求します。
    /// - Parameter newPermission: 新しい許可状態。
    private func applyPermission(_ newPermission: LocationPermission) {
        permission = newPermission
        if newPermission.level == .whenInUse && isAlwaysAuthorizationRequestPending {
            isAlwaysAuthorizationRequestPending = false
            authorization.requestAlwaysAuthorization()
        }
        section = RouteRecordingSettingsSection(isEnabled: section.isEnabled, permission: newPermission)
    }
}
