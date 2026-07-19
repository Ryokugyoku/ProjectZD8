#if os(macOS)
import SwiftUI

/// macOS設定画面へ渡す表示専用の選択状態です。
struct MacOSSettingsState: Equatable {
    /// 現在の表示言語です。
    var language: MacOSSettingsLanguage = .japanese

    /// 現在の外観モードです。
    var appearance: MacOSSettingsAppearance = .system

    /// 接続役割ごとに現在選択されているアダプターです。
    var selectedAdapters: [AdapterConnectionRole: DiscoveredAdapter] = [:]

    /// 次回起動時も優先するプライマリーアダプター設定です。
    var defaultAdapterPreference: DefaultAdapterPreference?

    /// アダプター候補一覧で選択中の接続方式です。
    var adapterTransportMode: AdapterTransportMode = .usb

    /// 選択中の接続方式で検出したアダプター候補です。
    var discoveredAdapters: [DiscoveredAdapter] = []

    /// 現在のアダプター探索状態です。
    var adapterDiscoveryStatus: MacOSAdapterDiscoveryStatus = .idle

    /// 現在アダプター選択シートを表示している接続役割です。
    var presentedAdapterSlot: AdapterConnectionRole?

    /// 接続情報の詳細を確認しているアダプター候補です。
    var inspectedAdapter: DiscoveredAdapter?

    /// 詳細表示中の候補が別の接続役割へ割り当て済みかどうかです。
    var hasAdapterAssignmentConflict = false

    /// HOMEの「アダプターを設定」ボタンを押すたびに増える強調要求番号です。
    var adapterAttentionSequence: UInt = 0

    /// 設定画面が1回だけ表示済みとして消費した強調要求番号です。
    var consumedAdapterAttentionSequence: UInt = 0

    /// 直前の「アダプターを設定」ボタン押下に対して1回だけ処理すべき強調要求が残っているかどうかです。
    var hasPendingAdapterAttention: Bool {
        adapterAttentionSequence > consumedAdapterAttentionSequence
    }
}

/// macOS設定画面に表示するアダプター探索状態です。
enum MacOSAdapterDiscoveryStatus: Equatable {
    /// 探索をまだ開始していません。
    case idle

    /// システムへアダプター候補を問い合わせています。
    case searching

    /// 最新の探索が完了しました。
    case loaded

    /// システムのデバイス情報へアクセスできませんでした。
    case failed
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
