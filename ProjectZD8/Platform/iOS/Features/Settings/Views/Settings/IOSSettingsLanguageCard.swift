#if os(iOS)
import SwiftUI

/// iOS設定画面で表示言語を切り替える設定カードを描画します。
struct IOSSettingsLanguageCard: View {
    /// 現在の表示言語です。
    let language: SettingsLanguage
    /// 表示言語が選ばれたことを通知するクロージャです。
    let select: (SettingsLanguage) -> Void

    /// 表示言語の分割ピッカーを持つカードを提供します。
    ///
    /// 責務: 表示言語の一覧を描画し、選ばれた言語を通知します。
    var body: some View {
        IOSSettingsCard(
            eyebrow: "settings.language.eyebrow",
            title: "settings.language.title",
            description: "settings.language.description",
            systemImage: "character.bubble.fill"
        ) {
            Picker(
                "settings.language.title",
                selection: Binding(
                    get: { language },
                    set: { select($0) }
                )
            ) {
                ForEach(SettingsLanguage.allCases) { language in
                    Text(language.title).tag(language)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .accessibilityIdentifier("ios-settings-language")
        }
    }
}
#endif
