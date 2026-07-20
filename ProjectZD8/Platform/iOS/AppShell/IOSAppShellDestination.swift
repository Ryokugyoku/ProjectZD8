#if os(iOS)
import SwiftUI

/// iOS AppShellに表示するプレゼンテーション専用の遷移先を識別します。
enum IOSAppShellDestination: String, CaseIterable, Identifiable {
    /// ホーム画面を選択します。
    case home

    /// リアルタイムログ画面を選択します。
    case liveLog

    /// 接続セッション履歴画面を選択します。
    case history

    /// 登録車両のGarage画面を選択します。
    case garage

    /// 設定画面を選択します。
    case settings

    /// 選択状態とアクセシビリティ参照に使う安定識別子です。
    var id: String { rawValue }

    /// 画面見出しに表示するローカライズ済み名称です。
    var title: LocalizedStringKey {
        switch self {
        case .home:
            "sidebar.home"
        case .liveLog:
            "sidebar.live_log"
        case .history:
            "sidebar.connection_history"
        case .garage:
            "sidebar.garage"
        case .settings:
            "sidebar.settings"
        }
    }

    /// 下部ナビゲーションに表示する短いローカライズ済み名称です。
    var compactTitle: LocalizedStringKey {
        switch self {
        case .home:
            "ios.navigation.home"
        case .liveLog:
            "ios.navigation.live_log"
        case .history:
            "ios.navigation.history"
        case .garage:
            "sidebar.garage"
        case .settings:
            "ios.navigation.settings"
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
        case .garage:
            "car.side.fill"
        case .settings:
            "slider.horizontal.3"
        }
    }
}
#endif
