#if os(macOS)
import SwiftUI

/// macOSサイドバーに表示するプレゼンテーション専用の遷移先を識別します。
enum MacOSSidebarDestination: String, CaseIterable, Identifiable {
    /// ホーム画面を選択します。
    case home

    /// リアルタイムログ画面を選択します。
    case liveLog

    /// 接続セッション履歴画面を選択します。
    case history

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
        case .history:
            "sidebar.connection_history"
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
        case .history:
            "sidebar.connection_history.subtitle"
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
        case .history:
            "clock.arrow.circlepath"
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
        case .history:
            "3"
        case .maintenance:
            "4"
        case .garage:
            "5"
        case .settings:
            "6"
        }
    }

    /// サイドバーに表示するキーボードショートカットの表記です。
    var shortcutLabel: String {
        switch self {
        case .home:
            "⌘1"
        case .liveLog:
            "⌘2"
        case .history:
            "⌘3"
        case .maintenance:
            "⌘4"
        case .garage:
            "⌘5"
        case .settings:
            "⌘6"
        }
    }
}
#endif
