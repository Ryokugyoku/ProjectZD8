#if os(macOS)
import SwiftUI

/// 車両別履歴ヘッダーの車両識別表示です。
struct MacOSConnectionHistoryVehicleSessionsIdentity: View {
    /// 表示する車両別履歴集計です。見つからない場合は未関連付け表示を使用します。
    let group: ConnectionHistoryVehicleGroup?
    /// 画面サイズに対応する表示倍率です。
    let scale: CGFloat

    /// 車両名称と表示識別子を整形します。
    private let textFormatter = ConnectionHistorySessionTextFormatter()

    /// シンボル、見出し、名称、表示識別子を描画します。
    ///
    /// 責務: 1件の車両グループを車両別履歴ヘッダー用の識別表示へ配置します。
    var body: some View {
        HStack(spacing: 14 * scale) {
            Image(systemName: "car.side.fill")
                .font(.system(size: 24 * scale, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 58 * scale, height: 58 * scale)
                .background(Color.accentColor.opacity(0.13), in: RoundedRectangle(cornerRadius: 18 * scale, style: .continuous))

            VStack(alignment: .leading, spacing: 4 * scale) {
                Text("history.archive.title")
                    .font(.system(size: 9.5 * scale, weight: .bold, design: .rounded))
                    .tracking(1.1 * scale)
                    .foregroundStyle(.tint)
                Text(textFormatter.vehicleGroupName(group?.vehicle))
                    .font(.system(size: 26 * scale, weight: .bold, design: .rounded))
                    .lineLimit(1)
                if let identifier = textFormatter.vehicleIdentifier(group?.vehicle) {
                    Text(identifier)
                        .font(.system(size: 10 * scale, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}
#endif
