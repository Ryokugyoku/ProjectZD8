#if os(iOS)
import SwiftUI

/// iOS設定画面でプライマリーと受信専用セカンダリーのアダプターを示す設定カードを描画します。
struct IOSSettingsAdapterCard: View {
    /// スクロール対象として使うアダプター設定カードの識別子です。
    static let scrollID = "ios-settings-adapter-card"

    /// 接続役割ごとに選択されているアダプターです。
    let selectedAdapters: [AdapterConnectionRole: DiscoveredAdapter]
    /// 振動アニメーションの進行値です。動きを抑える設定の時は0を渡します。
    let attentionProgress: CGFloat
    /// アダプタースロットの選択が求められたことを通知するクロージャです。
    let requestSelection: (AdapterConnectionRole) -> Void

    /// 2つのアダプター行を持ち、注目要求で振動するカードを提供します。
    ///
    /// 責務: スロットごとの説明を純粋型で決めて行を並べ、スクロール識別子と振動効果を付けます。
    var body: some View {
        IOSSettingsCard(
            eyebrow: "settings.adapter.eyebrow",
            title: "settings.adapter.title",
            description: "settings.adapter.description",
            systemImage: "cable.connector.horizontal"
        ) {
            VStack(spacing: IOSSettingsMetrics.adapterRowListSpacing) {
                row(for: .primary)
                row(for: .secondary)
            }
        }
        .id(Self.scrollID)
        .accessibilityIdentifier(Self.scrollID)
        .modifier(AttentionShakeEffect(progress: attentionProgress, amplitude: IOSSettingsMetrics.attentionShakeAmplitude))
    }

    /// 1件のアダプタースロットの行を作ります。
    ///
    /// 責務: スロットの説明を決めて行へ渡し、押されたらそのスロットの選択を求めます。
    /// - Parameter slot: 行が表すアダプタースロット。
    /// - Returns: アダプター行。
    private func row(for slot: AdapterConnectionRole) -> some View {
        IOSSettingsAdapterRow(
            slot: slot,
            description: AdapterSlotSettingsDescription(slot: slot, selectedAdapters: selectedAdapters)
        ) {
            requestSelection(slot)
        }
    }
}
#endif
