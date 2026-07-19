#if os(macOS)
import SwiftUI

/// macOSサイドバーに表示するプレゼンテーション専用の遷移先を識別します。
enum MacOSSidebarDestination: String, CaseIterable, Identifiable {
    /// ホーム画面を選択します。
    case home

    /// リアルタイムログ画面を選択します。
    case liveLog

    /// 整備画面を選択します。
    case maintenance

    /// 複数車両のGarage画面を選択します。
    case garage

    /// 設定画面を選択します。
    case settings

    /// 選択状態とアクセシビリティ参照に使う安定識別子です。
    var id: String { rawValue }

    /// 遷移先のローカライズ済みタイトルです。
    var title: LocalizedStringKey {
        switch self {
        case .home:
            "sidebar.home"
        case .liveLog:
            "sidebar.live_log"
        case .maintenance:
            "sidebar.maintenance"
        case .garage:
            "sidebar.garage"
        case .settings:
            "sidebar.settings"
        }
    }

    /// 遷移先の役割を補足するローカライズ済み短文です。
    var subtitle: LocalizedStringKey {
        switch self {
        case .home:
            "sidebar.home.subtitle"
        case .liveLog:
            "sidebar.live_log.subtitle"
        case .maintenance:
            "sidebar.maintenance.subtitle"
        case .garage:
            "sidebar.garage.subtitle"
        case .settings:
            "sidebar.settings.subtitle"
        }
    }

    /// 遷移先を表すSF Symbol名です。
    var systemImage: String {
        switch self {
        case .home:
            "house.fill"
        case .liveLog:
            "waveform.path.ecg"
        case .maintenance:
            "wrench.adjustable.fill"
        case .garage:
            "car.2.fill"
        case .settings:
            "slider.horizontal.3"
        }
    }

    /// 遷移先を直接選択するCommandキーとの組み合わせ番号です。
    var shortcut: KeyEquivalent {
        switch self {
        case .home:
            "1"
        case .liveLog:
            "2"
        case .maintenance:
            "3"
        case .garage:
            "4"
        case .settings:
            "5"
        }
    }

    /// サイドバーに表示するキーボードショートカットの表記です。
    var shortcutLabel: String {
        switch self {
        case .home:
            "⌘1"
        case .liveLog:
            "⌘2"
        case .maintenance:
            "⌘3"
        case .garage:
            "⌘4"
        case .settings:
            "⌘5"
        }
    }
}
#endif
