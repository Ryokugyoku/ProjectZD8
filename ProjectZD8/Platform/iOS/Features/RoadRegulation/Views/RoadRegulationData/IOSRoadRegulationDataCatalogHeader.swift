#if os(iOS)
import SwiftUI

/// iOSの交通規制データの管理画面で、「更新を確認」ボタンと一覧の確認の状態を描画します。
///
/// ボタンの可否と文言の選択は `RoadRegulationCatalogHeaderContent` が持ち、この型は描画と操作の通知だけを行います。
struct IOSRoadRegulationDataCatalogHeader: View {
    /// 欄に出す内容です。
    let content: RoadRegulationCatalogHeaderContent
    /// 「更新を確認」が押されたことを通知するクロージャです。
    let check: () -> Void

    /// ボタンと状態の文言を縦に並べた欄を提供します。
    ///
    /// 責務: 確認中は進行中の印を出してボタンを押せなくし、失敗ならアイコンだけをオレンジで強調します。
    var body: some View {
        VStack(alignment: .leading, spacing: IOSRoadRegulationDataMetrics.catalogHeaderSpacing) {
            Button(action: check) {
                Label(LocalizedStringKey(RoadRegulationCatalogHeaderContent.buttonKey), systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(!content.canCheck)
            .accessibilityIdentifier("ios-road-regulation-check-updates")
            if let statusKey = content.statusKey {
                statusRow(key: statusKey)
            }
        }
    }

    /// 確認の状態の1行を作ります。
    ///
    /// 責務: 確認中なら進行中の印、失敗なら注意の印、確認済みなら完了の印を文言の前に置きます。
    /// - Parameter key: 状態の文言キー。
    /// - Returns: 状態の1行。
    private func statusRow(key: String) -> some View {
        HStack(spacing: IOSRoadRegulationDataMetrics.catalogHeaderSpacing) {
            if content.isChecking {
                ProgressView()
            } else {
                Image(systemName: content.isFailure ? "exclamationmark.triangle.fill" : "checkmark.circle")
                    .foregroundStyle(content.isFailure ? Color.orange : Color.secondary)
            }
            Text(LocalizedStringKey(key))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.footnote)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("ios-road-regulation-catalog-status")
    }
}
#endif
