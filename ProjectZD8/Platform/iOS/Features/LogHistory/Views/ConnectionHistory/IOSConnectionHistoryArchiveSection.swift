#if os(iOS)
import SwiftUI

/// 終了済みセッションを車両単位のカードとして示すアーカイブセクションです。
struct IOSConnectionHistoryArchiveSection: View {
    /// 表示する車両別履歴集計です。
    let groups: [ConnectionHistoryVehicleGroup]

    /// 車両グループの識別子を accessibilityIdentifier 用に整形します。
    private let textFormatter = ConnectionHistorySessionTextFormatter()

    /// 見出しと、車両別一覧へ遷移するカード、または空表示を描画します。
    ///
    /// 責務: 車両別履歴集計の列を見出し付きの遷移カード列へ配置します。
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            IOSConnectionHistorySectionTitle(titleKey: "history.archive.title", systemImage: "car.2.fill")
            if groups.isEmpty {
                Text("history.archive.empty")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .padding(20).frame(maxWidth: .infinity)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else {
                ForEach(groups) { group in
                    NavigationLink(value: group.id) { IOSConnectionHistoryVehicleGroupCard(group: group) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("ios-history-vehicle-\(textFormatter.groupIdentifier(group.id))")
                }
            }
        }
    }
}
#endif
