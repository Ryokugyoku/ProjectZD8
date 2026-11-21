#if os(iOS)
import SwiftUI

/// iPhone のセッション詳細で、静的性能解析の画面へ進む操作を表示します。
struct IOSConnectionSessionDetailAnalysisButton: View {
    /// 解析を開く操作を送出します。
    let onOpen: () -> Void

    /// アイコン、見出し、補足、矢印を持つ解析への導線を描画します。
    ///
    /// 責務: 押すと解析を開く操作を送出する、カード状のボタンを描画します。
    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 13) {
                Image(systemName: "chart.xyaxis.line")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.indigo)
                    .frame(width: 44, height: 44)
                    .background(Color.indigo.opacity(0.11), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("analysis.open").font(.headline)
                    Text("analysis.open.hint").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.indigo.opacity(0.16)) }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ios-history-open-analysis")
    }
}
#endif
