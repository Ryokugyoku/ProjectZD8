#if os(macOS)
import SwiftUI

/// macOSの交通規制データの管理画面で、「更新を確認」ボタンと一覧の確認の状態を描画します。
///
/// ボタンの可否と文言の選択は `RoadRegulationCatalogHeaderContent` が持ち、この型は描画と操作の通知だけを行います。
struct MacOSRoadRegulationDataCatalogHeader: View {
    /// 欄に出す内容です。
    let content: RoadRegulationCatalogHeaderContent
    /// 「更新を確認」が押されたことを通知するクロージャです。
    let check: () -> Void
    /// ウインドウ寸法に応じた拡大率を持つ寸法です。
    let metrics: MacOSAppShellMetrics

    /// ボタンと状態の文言を横に並べた欄を提供します。
    ///
    /// 責務: 確認中は進行中の印を出してボタンを押せなくし、失敗ならアイコンだけをオレンジで強調します。
    var body: some View {
        HStack(spacing: MacOSRoadRegulationDataMetrics.sectionSpacing * metrics.scale) {
            Button(action: check) {
                Label(LocalizedStringKey(RoadRegulationCatalogHeaderContent.buttonKey), systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.bordered)
            .disabled(!content.canCheck)
            .accessibilityIdentifier("macos-road-regulation-check-updates")
            if let statusKey = content.statusKey {
                statusRow(key: statusKey)
            }
            Spacer(minLength: 0)
        }
    }

    /// 確認の状態の1行を作ります。
    ///
    /// 責務: 確認中なら進行中の印、失敗なら注意の印、確認済みなら完了の印を文言の前に置きます。
    /// - Parameter key: 状態の文言キー。
    /// - Returns: 状態の1行。
    private func statusRow(key: String) -> some View {
        HStack(spacing: MacOSRoadRegulationDataMetrics.progressSpacing * metrics.scale) {
            if content.isChecking {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: content.isFailure ? "exclamationmark.triangle.fill" : "checkmark.circle")
                    .foregroundStyle(content.isFailure ? Color.orange : Color.secondary)
            }
            Text(LocalizedStringKey(key))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: MacOSRoadRegulationDataMetrics.captionFontSize * metrics.scale))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("macos-road-regulation-catalog-status")
    }
}
#endif
