/// 設定画面の「エンジン停止の判定時間」区画に表示する内容です。
///
/// SwiftUI に依存せず、文言はローカライズキーで返します(View で `LocalizedStringKey` に変換します)。
struct VehicleOffDetectionSettingsSection: Equatable, Sendable {
    /// 区画の種別を短く示すローカライズキーです。
    static let eyebrowKey = "settings.vehicle_off.eyebrow"
    /// 区画の見出しを表すローカライズキーです。
    static let titleKey = "settings.vehicle_off.title"
    /// 区画の目的を補足するローカライズキーです。
    static let descriptionKey = "settings.vehicle_off.description"

    /// 現在保存されている時間です。
    let selectedDelay: VehicleOffDetectionDelay

    /// 表示順に並べた選択肢です。
    var choices: [VehicleOffDetectionDelay] { VehicleOffDetectionDelay.allCases }

    /// 保存済みの時間から区画内容を生成します。
    ///
    /// 責務: 現在の時間を選択状態の表示内容へ変換します。
    /// - Parameter selectedDelay: 保存済みの時間。
    init(selectedDelay: VehicleOffDetectionDelay) {
        self.selectedDelay = selectedDelay
    }

    /// 指定した時間が現在の保存値かどうかを返します。
    ///
    /// 責務: 1件の選択肢を選択状態の表示可否へ変換します。
    /// - Parameter delay: 判定する時間。
    /// - Returns: 保存値と一致する場合は `true`。
    func isSelected(_ delay: VehicleOffDetectionDelay) -> Bool {
        delay == selectedDelay
    }

    /// 選択肢の表示名を表すローカライズキーを返します。
    ///
    /// 責務: 1件の時間を対応する「◯秒」のローカライズキーへ写像します。
    /// - Parameter delay: 表示する時間。
    /// - Returns: ローカライズキー。
    static func titleKey(for delay: VehicleOffDetectionDelay) -> String {
        "settings.vehicle_off.delay.\(delay.rawValue)"
    }
}
