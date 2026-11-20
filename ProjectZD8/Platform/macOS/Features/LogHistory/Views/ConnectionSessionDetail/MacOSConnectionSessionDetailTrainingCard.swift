#if os(macOS)
import SwiftUI

/// macOS のセッション詳細で、車両単位の学習データ抽出の準備状態を大きなカードで表示します。
struct MacOSConnectionSessionDetailTrainingCard: View {
    /// 画面サイズに対応する表示倍率です。
    let scale: CGFloat
    /// 車両別の学習抽出へ使用できるかを示します。
    let isTrainingReady: Bool
    /// セッションの車両が確定しているかを示します。
    let hasVehicle: Bool

    /// アイコン、説明、抽出の単位を横に並べて描画します。
    ///
    /// 責務: 学習準備の可否に応じた色と本文で、学習準備のカードを描画します。
    var body: some View {
        HStack(spacing: 20 * scale) {
            ZStack {
                RoundedRectangle(cornerRadius: 22 * scale, style: .continuous)
                    .fill(readinessColor.opacity(0.13))
                Image(systemName: "brain.head.profile.fill")
                    .font(.system(size: 35 * scale, weight: .semibold))
                    .foregroundStyle(readinessColor)
            }
            .frame(width: 76 * scale, height: 76 * scale)
            VStack(alignment: .leading, spacing: 7 * scale) {
                Text("history.training.title")
                    .font(.system(size: 20 * scale, weight: .bold, design: .rounded))
                Text(isTrainingReady ? "history.training.ready.body" : "history.training.pending.body")
                    .font(.system(size: 13 * scale, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12 * scale)
            scopeColumn
        }
        .padding(22 * scale)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24 * scale, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24 * scale, style: .continuous)
                .stroke(readinessColor.opacity(0.22))
        }
    }

    /// 学習抽出の単位を示す右端の列です。
    private var scopeColumn: some View {
        VStack(alignment: .trailing, spacing: 5 * scale) {
            Text("history.training.scope")
                .font(.system(size: 9 * scale, weight: .bold))
                .foregroundStyle(.tertiary)
            Text(hasVehicle ? "VEHICLE / SESSION / SEQUENCE" : "—")
                .font(.system(size: 10 * scale, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    /// 学習準備の可否に対応するアクセント色です。準備済みは緑、未準備はオレンジです。
    private var readinessColor: Color {
        isTrainingReady ? Color.green : Color.orange
    }
}
#endif
