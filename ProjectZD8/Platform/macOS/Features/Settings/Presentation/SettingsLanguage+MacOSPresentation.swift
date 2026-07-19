#if os(macOS)
import SwiftUI

/// 共通言語設定へmacOS表示情報を付加します。
extension SettingsLanguage {
    /// 言語選択肢に表示するローカライズ済み名称です。
    var title: LocalizedStringKey {
        switch self {
        case .japanese:
            "settings.language.japanese"
        case .english:
            "settings.language.english"
        case .spanish:
            "settings.language.spanish"
        }
    }

    /// SwiftUIのロケール環境へ渡す言語識別子です。
    var localeIdentifier: String {
        switch self {
        case .japanese:
            "ja"
        case .english:
            "en"
        case .spanish:
            "es"
        }
    }
}
#endif
