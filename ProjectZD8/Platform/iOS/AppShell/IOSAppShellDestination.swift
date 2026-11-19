#if os(iOS)
import SwiftUI

/// iOS AppShellに表示するプレゼンテーション専用の遷移先を識別します。
enum IOSAppShellDestination: String, CaseIterable, Identifiable {
    /// 接続とリアルタイム表示をまとめたホーム画面を選択します。
    case home

    /// 接続セッション履歴画面を選択します。
    case history

    /// 車両別の軽整備と重整備画面を選択します。
    case maintenance

    /// 登録車両のGarage画面を選択します。
    case garage

    /// 設定画面を選択します。
    case settings

    /// 選択状態とアクセシビリティ参照に使う安定識別子です。
    var id: String { rawValue }

    /// 下部ナビゲーションに表示する短いローカライズ済み名称です。
    var compactTitle: LocalizedStringKey {
        switch self {
        case .home:
            "ios.navigation.home"
        case .history:
            "ios.navigation.history"
        case .maintenance:
            "ios.navigation.maintenance"
        case .garage:
            "sidebar.garage"
        case .settings:
            "ios.navigation.settings"
        }
    }

    /// 遷移先を表すSF Symbol名です。
    var systemImage: String {
        switch self {
        case .home:
            "house.fill"
        case .history:
            "clock.arrow.circlepath"
        case .maintenance:
            "wrench.and.screwdriver.fill"
        case .garage:
            "car.side.fill"
        case .settings:
            "slider.horizontal.3"
        }
    }
}
#endif
