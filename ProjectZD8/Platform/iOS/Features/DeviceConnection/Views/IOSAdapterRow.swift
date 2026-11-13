#if os(iOS)
import SwiftUI

/// 探索で見つかったアダプター1件の行です。
struct IOSAdapterRow: View {
    let adapter: AdapterDescriptor
    let isDefault: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: InsightSpacing.md) {
                Image(systemName: adapter.transport.iosSymbolName)
                    .font(.title3)
                    .foregroundStyle(InsightPalette.accent)
                    .frame(width: InsightSpacing.minimumHitTarget - InsightSpacing.sm)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: InsightSpacing.xxs) {
                    Text(verbatim: adapter.displayName)
                        .font(InsightTypography.body)
                        .foregroundStyle(.primary)
                    HStack(spacing: InsightSpacing.xs) {
                        Text(LocalizedStringKey(adapter.transport.iosNameKey))
                        if let detail = adapter.detail {
                            Text(verbatim: "·")
                            Text(verbatim: detail)
                        }
                    }
                    .font(InsightTypography.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: InsightSpacing.sm)
                if adapter.transport == .demo {
                    StatusBadge(Text("device.adapter.demo"), tone: .warning)
                }
                if isDefault {
                    StatusBadge(Text("device.adapter.default"), tone: .active, symbol: "checkmark.circle.fill")
                }
            }
            .frame(minHeight: InsightSpacing.minimumHitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}
#endif
