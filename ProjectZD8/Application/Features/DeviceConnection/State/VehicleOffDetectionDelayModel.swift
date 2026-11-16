import Observation

/// 「エンジン停止とみなす時間」の設定操作を保存と表示内容へ変換します。
@MainActor
@Observable
final class VehicleOffDetectionDelayModel {
    /// 設定画面が描画する現在の区画内容です。
    private(set) var section: VehicleOffDetectionSettingsSection

    /// 設定の読み書きを行うユースケースです。
    @ObservationIgnored
    private let preference: VehicleOffDetectionDelayPreferenceUseCase

    /// ユースケースを注入し、保存済みの値を読み込んで生成します。
    ///
    /// 責務: 保存済みの時間を初期の表示内容へ反映します。
    /// - Parameter preference: 設定の読み書きを行うユースケース。
    init(preference: VehicleOffDetectionDelayPreferenceUseCase) {
        self.preference = preference
        section = VehicleOffDetectionSettingsSection(selectedDelay: preference.load())
    }

    /// 受け取った操作を保存と表示内容へ反映します。
    ///
    /// 責務: 選ばれた時間を保存し、保存境界から読み直した値だけを表示へ使います。
    /// - Parameter action: 設定画面から通知された型付き操作。
    func send(_ action: VehicleOffDetectionDelayAction) {
        switch action {
        case let .delaySelected(delay):
            preference.save(delay)
            section = VehicleOffDetectionSettingsSection(selectedDelay: preference.load())
        }
    }
}
