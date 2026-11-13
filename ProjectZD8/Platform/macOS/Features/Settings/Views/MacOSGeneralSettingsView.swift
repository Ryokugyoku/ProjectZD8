#if os(macOS)
import SwiftUI

/// 「一般」タブ: 外観・デモモード・端末内 Raw の保持期間。
struct MacOSGeneralSettingsView: View {
    let state: SettingsState
    let send: (SettingsAction) -> Void

    var body: some View {
        Form {
            Section {
                Picker(selection: Binding(
                    get: { state.settings.appearance },
                    set: { send(.appearanceChanged($0)) }
                )) {
                    ForEach(SettingsState.appearanceOptions) { option in
                        Text(LocalizedStringKey(option.nameKey)).tag(option.value)
                    }
                } label: {
                    Text("settings.appearance.title")
                }
            }

            Section {
                Toggle(isOn: Binding(
                    get: { state.settings.isDemoModeEnabled },
                    set: { send(.demoModeChanged($0)) }
                )) {
                    Text("settings.demo.title")
                }
                Text("settings.demo.description")
                    .font(InsightTypography.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("settings.demo.header")
            }

            Section {
                Picker(selection: Binding(
                    get: { state.settings.localRawRetention },
                    set: { send(.localRawRetentionChanged($0)) }
                )) {
                    ForEach(SettingsState.retentionOptions) { option in
                        Text(LocalizedStringKey(option.nameKey)).tag(option.value)
                    }
                } label: {
                    Text("settings.retention.title")
                }
                Text("settings.retention.description")
                    .font(InsightTypography.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("settings.retention.header")
            }
        }
        .formStyle(.grouped)
    }
}
#endif
