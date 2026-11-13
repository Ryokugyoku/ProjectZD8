#if os(iOS)
import SwiftUI

/// 外観・デモモード・Raw保持・既定アダプター・iCloud・Aboutをまとめた設定画面です。
struct IOSSettingsScreen: View {
    let settings: SettingsState
    let devices: DeviceConnectionState
    let sync: SyncState
    let sendSettings: (SettingsAction) -> Void
    let sendDevice: (DeviceConnectionAction) -> Void
    let sendSync: (SyncAction) -> Void

    var body: some View {
        NavigationStack {
            Form {
                appearanceSection
                dataSection
                IOSSettingsAdapterSection(state: devices, send: sendDevice)
                IOSSyncSection(state: sync, send: sendSync)
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(InsightBackground())
            .navigationTitle(Text("tab.settings"))
        }
    }

    private var appearanceSection: some View {
        Section {
            Picker(
                "settings.appearance.title",
                selection: Binding(get: { settings.settings.appearance }, set: { sendSettings(.appearanceChanged($0)) })
            ) {
                ForEach(SettingsState.appearanceOptions) { option in
                    Text(LocalizedStringKey(option.nameKey)).tag(option.value)
                }
            }
        } header: {
            Text("settings.appearance.header")
        }
    }

    private var dataSection: some View {
        Section {
            Toggle(
                "settings.demo.title",
                isOn: Binding(get: { settings.settings.isDemoModeEnabled }, set: { sendSettings(.demoModeChanged($0)) })
            )
            Picker(
                "settings.retention.title",
                selection: Binding(get: { settings.settings.localRawRetention }, set: { sendSettings(.localRawRetentionChanged($0)) })
            ) {
                ForEach(SettingsState.retentionOptions) { option in
                    Text(LocalizedStringKey(option.nameKey)).tag(option.value)
                }
            }
        } header: {
            Text("settings.data.header")
        } footer: {
            VStack(alignment: .leading, spacing: InsightSpacing.sm) {
                Text("settings.demo.footer")
                Text("settings.retention.footer")
            }
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("settings.about.version") {
                Text(verbatim: settings.versionText).monospacedDigit()
            }
        } header: {
            Text("settings.about.header")
        }
    }
}
#endif
