#if os(iOS)
import SwiftUI

/// 車両不明ログの紐付け画面で、紐付け先の候補の車両1台と選択状態を描画する行です。
struct IOSVehicleUnknownSessionAssignmentVehicleRow: View {
    /// 描画する車両です。
    let vehicle: VehicleProfile
    /// 選ばれているかどうかです。
    let isSelected: Bool
    /// 選んだことを通知するクロージャです。
    let select: () -> Void

    /// 車両の名前と識別子、選択の印を提供します。
    ///
    /// 責務: 1台の車両を描画し、タップで選んだことを通知します。
    var body: some View {
        Button(action: select) {
            HStack {
                VStack(alignment: .leading, spacing: IOSVehicleUnknownSessionMetrics.rowSpacing) {
                    Text(vehicle.name).font(.body)
                    Text(vehicle.displayIdentifier)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark").foregroundStyle(Color.cyan)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
#endif
