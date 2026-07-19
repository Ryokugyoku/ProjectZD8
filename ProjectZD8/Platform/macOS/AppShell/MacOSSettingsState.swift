#if os(macOS)
import SwiftUI

/// macOS設定画面へ渡す表示専用の選択状態です。
struct MacOSSettingsState: Equatable {
    /// 現在の表示言語です。
    var language: MacOSSettingsLanguage = .japanese

    /// 現在の外観モードです。
    var appearance: MacOSSettingsAppearance = .system
}

/// macOS設定画面で選択できる表示言語です。
enum MacOSSettingsLanguage: String, CaseIterable, Identifiable {
    /// 日本語表示を選択します。
    case japanese

    /// 英語表示を選択します。
    case english

    /// スペイン語表示を選択します。
    case spanish

    /// 選択状態とアクセシビリティ参照に使う安定識別子です。
    var id: String { rawValue }

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

/// macOS設定画面で選択できる外観モードです。
enum MacOSSettingsAppearance: String, CaseIterable, Identifiable {
    /// macOSの外観設定へ追従します。
    case system

    /// 明るい外観を選択します。
    case light

    /// 暗い外観を選択します。
    case dark

    /// 選択状態とアクセシビリティ参照に使う安定識別子です。
    var id: String { rawValue }

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

    /// SwiftUIの優先カラースキームへ渡す値です。
    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }
}
#endif
