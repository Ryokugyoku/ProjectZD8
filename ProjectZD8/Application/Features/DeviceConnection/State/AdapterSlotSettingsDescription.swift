/// 設定画面のアダプター行に出す、1件のアダプタースロットの説明です。SwiftUIに依存しない純粋型で、iOSとmacOSで共有します。
///
/// アダプター名は機器が名乗る任意の文字列なのでローカライズキーとして扱いません(`%` などを含んでも崩さず、そのまま表示します)。
/// 未選択の時だけローカライズキーを返し、View側で `LocalizedStringKey` へ変換します。
enum AdapterSlotSettingsDescription: Equatable {
    /// 未選択を表す文言のローカライズキーです。
    static let notSelectedKey = "settings.adapter.not_selected"

    /// 選択済みアダプターの名前です。そのまま(ローカライズせずに)表示します。
    case adapterName(String)
    /// ローカライズキーの文言です。
    case localizationKey(String)

    /// スロットに選択されているアダプターから説明を決めます。
    ///
    /// 責務: 選択済みならアダプターの表示名、未選択なら未選択の文言キーへ変換します。
    /// - Parameters:
    ///   - slot: 説明するアダプタースロット。
    ///   - selectedAdapters: 接続役割ごとに選択されているアダプター。
    init(slot: AdapterConnectionRole, selectedAdapters: [AdapterConnectionRole: DiscoveredAdapter]) {
        if let adapter = selectedAdapters[slot] {
            self = .adapterName(adapter.displayName)
        } else {
            self = .localizationKey(Self.notSelectedKey)
        }
    }
}
