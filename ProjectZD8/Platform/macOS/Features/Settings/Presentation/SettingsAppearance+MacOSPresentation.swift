#if os(macOS)
import SwiftUI

/// 共通外観設定へmacOS表示情報を付加します。
extension SettingsAppearance {
    /// 外観選択肢に表示するローカライズ済み名称です。
    var title: LocalizedStringKey {
        switch self {
        case .system:
            "settings.appearance.system"
        case .light:
            "settings.appearance.light"
        case .dark:
            "settings.appearance.dark"
        }
    }

    /// 外観選択肢を表すSF Symbol名です。
    var systemImage: String {
        switch self {
        case .system:
            "circle.lefthalf.filled"
        case .light:
            "sun.max.fill"
        case .dark:
            "moon.stars.fill"
        }
    }
}
#endif
