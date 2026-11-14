#if os(macOS)
import SwiftUI

/// 終了済みセッションを車両単位のグリッドとして示すアーカイブセクションです。
struct MacOSConnectionHistoryArchiveSection: View {
    /// 表示する車両別履歴集計です。
    let groups: [ConnectionHistoryVehicleGroup]
    /// 画面サイズに対応する表示倍率です。
    let scale: CGFloat

    /// 車両グループのUI識別文字列を生成します。
    private let textFormatter = ConnectionHistorySessionTextFormatter()

    /// 見出しと車両カードのグリッド、または空表示を描画します。
    ///
    /// 責務: 車両別履歴集計列を車両別一覧へ遷移できるカードグリッドへ配置します。
    var body: some View {
        VStack(alignment: .leading, spacing: 13 * scale) {
            MacOSConnectionHistorySectionTitle(titleKey: "history.archive.title", systemImage: "car.2.fill", scale: scale)
            if groups.isEmpty {
                Text("history.archive.empty").foregroundStyle(.secondary).padding(24 * scale).frame(maxWidth: .infinity)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 20 * scale, style: .continuous))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300 * scale), spacing: 14 * scale)], spacing: 14 * scale) {
                    ForEach(groups) { group in
                        NavigationLink(value: MacOSConnectionHistoryRoute.vehicleSessions(group.id)) {
                            MacOSConnectionHistoryVehicleGroupCard(group: group, scale: scale)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("macos-history-vehicle-\(textFormatter.groupIdentifier(group.id))")
                    }
                }
            }
        }
    }
}
#endif
