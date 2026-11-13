#if os(macOS)
import SwiftUI

/// ネイティブのサイドバー(遷移先一覧・同期状態・記録インジケーター)。
struct MacOSSidebarView: View {
    @Binding var selection: MacOSDestination
    let isRecording: Bool
    let sync: SyncState

    var body: some View {
        List(MacOSDestination.allCases, selection: Binding<MacOSDestination?>(
            get: { selection },
            set: { if let value = $0 { selection = value } }
        )) { destination in
            Label {
                Text(destination.titleKey)
            } icon: {
                Image(systemName: destination.symbol)
            }
            .badge(destination == .drive && isRecording ? Text("shell.recording") : nil)
            .tag(destination)
        }
        .navigationSplitViewColumnWidth(
            min: MacOSAppShellMetrics.sidebarWidth.min,
            ideal: MacOSAppShellMetrics.sidebarWidth.ideal,
            max: MacOSAppShellMetrics.sidebarWidth.max
        )
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: InsightSpacing.sm) {
                if isRecording { MacOSRecordingIndicator() }
                MacOSSyncStatusFooter(state: sync)
            }
            .padding(InsightSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
#endif
