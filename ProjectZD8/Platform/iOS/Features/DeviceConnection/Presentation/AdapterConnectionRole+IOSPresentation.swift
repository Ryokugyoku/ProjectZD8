#if os(iOS)
import SwiftUI

/// 共通接続役割へiOS設定画面固有の表示情報を付与します。
extension AdapterConnectionRole {
    /// iOS設定画面に表示するローカライズ済み名称です。
    var title: LocalizedStringKey {
        switch self {
        case .primary:
            "settings.adapter.primary"
        case .secondary:
            "settings.adapter.secondary"
        }
    }

    /// iOS設定画面に表示する制約のローカライズ済み短文です。
    var badge: LocalizedStringKey {
        switch self {
        case .primary:
            "settings.adapter.required"
        case .secondary:
            "settings.adapter.receive_only"
        }
    }

    /// iOS設定画面で接続役割を表すSF Symbol名です。
    var systemImage: String {
        switch self {
        case .primary:
            "bolt.horizontal.circle.fill"
        case .secondary:
            "wave.3.right.circle"
        }
    }
}
#endif
