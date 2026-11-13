#if os(iOS)
import SwiftUI

/// PID収集設定の1行です。車両が応答を確認していないPIDは切り替えられません。
struct IOSVehiclePIDSettingRow: View {
    let item: VehiclePIDSettingItem
    let onToggle: (Bool) -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { item.isEnabled }, set: onToggle)) {
            VStack(alignment: .leading, spacing: InsightSpacing.xs) {
                HStack(spacing: InsightSpacing.sm) {
                    Text(LocalizedStringKey(item.nameKey)).font(InsightTypography.body)
                    if item.isVehicleSpecific {
                        StatusBadge(Text("garage.pid_settings.vehicleSpecific"), tone: .active)
                    }
                }
                HStack(spacing: InsightSpacing.sm) {
                    if !item.unit.isEmpty {
                        Text(verbatim: item.unit)
                        Text(verbatim: "·")
                    }
                    Text(verbatim: String(format: "%02X %02X", item.request.service, item.request.pid))
                        .font(.caption.monospaced())
                    Text(verbatim: "·")
                    Text(LocalizedStringKey(supportKey))
                }
                .font(InsightTypography.caption)
                .foregroundStyle(.secondary)
            }
        }
        .disabled(!item.isSupported)
        .accessibilityElement(children: .combine)
    }

    /// 車両の応答確認状態の表示キーです。
    private var supportKey: String {
        switch item.support {
        case .supported: "garage.pid_settings.support.supported"
        case .unsupported: "garage.pid_settings.support.unsupported"
        case .unknown: "garage.pid_settings.support.unknown"
        }
    }
}
#endif
