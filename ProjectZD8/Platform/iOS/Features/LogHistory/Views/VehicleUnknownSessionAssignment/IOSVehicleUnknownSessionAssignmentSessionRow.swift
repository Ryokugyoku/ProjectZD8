#if os(iOS)
import SwiftUI

/// 車両不明ログの紐付け画面で、1件のログと選択状態を描画する行です。
struct IOSVehicleUnknownSessionAssignmentSessionRow: View {
    /// 描画するログです。
    let session: ConnectionSession
    /// 選ばれているかどうかです。
    let isSelected: Bool
    /// 選択を切り替えたことを通知するクロージャです。
    let toggle: () -> Void

    /// ログの開始日時と識別子、選択の印を提供します。
    ///
    /// 責務: 1件のログを描画し、タップで選択の切り替えを通知します。
    var body: some View {
        Button(action: toggle) {
            HStack {
                VStack(alignment: .leading, spacing: IOSVehicleUnknownSessionMetrics.rowSpacing) {
                    Text(session.startedAt, format: .dateTime.year().month().day().hour().minute())
                        .font(.body)
                    Text(ConnectionHistorySessionTextFormatter().shortID(session.id))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.cyan : Color.secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
#endif
