#if os(iOS)
import SwiftUI

/// iOS設定画面へ渡す表示専用の選択状態です。
struct IOSSettingsState: Equatable {
    /// 現在の表示言語です。
    var language: IOSSettingsLanguage = .japanese

    /// 現在の外観モードです。
    var appearance: IOSSettingsAppearance = .system

    /// 接続役割ごとに現在選択されているBluetoothアダプター候補です。
    var selectedAdapters: [AdapterConnectionRole: DiscoveredAdapter] = [:]

    /// 最新のBluetooth探索で検出した候補です。
    var discoveredAdapters: [DiscoveredAdapter] = []

    /// 現在のBluetooth探索表示状態です。
    var bluetoothDiscoveryStatus: IOSBluetoothDiscoveryStatus = .idle

    /// Bluetoothアダプター選択画面で設定対象にしているスロットです。
    var presentedAdapterSlot: AdapterConnectionRole?

    /// 接続情報の詳細を確認しているBluetooth候補です。
    var inspectedAdapter: DiscoveredAdapter?

    /// 詳細表示中の候補が別の接続役割へ割り当て済みかどうかです。
    var hasAdapterAssignmentConflict = false
}

/// iOS設定画面に表示するBluetooth探索状態です。
enum IOSBluetoothDiscoveryStatus: Equatable {
    /// Bluetooth探索をまだ開始していません。
    case idle

    /// Bluetooth候補を非同期に探索しています。
    case searching

    /// 最新のBluetooth探索が完了しました。
    case loaded

    /// Bluetoothを利用できない理由が判明しました。
    case unavailable(IOSBluetoothUnavailableReason)

    /// Bluetooth状態以外の理由で探索を完了できませんでした。
    case failed
}

/// iOSでBluetooth探索を利用できない理由を表示用に表します。
enum IOSBluetoothUnavailableReason: Equatable {
    /// Bluetoothがシステム設定で無効です。
    case poweredOff

    /// Bluetooth利用が許可されていません。
    case unauthorized

    /// 実行環境がBluetooth Low Energy中央デバイス機能に対応していません。
    case unsupported
}

/// iOS設定画面で選択できる表示言語です。
enum IOSSettingsLanguage: String, CaseIterable, Identifiable {
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

/// iOS設定画面で選択できる外観モードです。
enum IOSSettingsAppearance: String, CaseIterable, Identifiable {
    /// iOSの外観設定へ追従します。
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
