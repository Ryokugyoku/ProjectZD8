#if os(iOS)
import SwiftUI

/// PIDの概要と確認の観点を4項目で示す説明シートです。
struct IOSLiveTelemetryPanelHelpSheet: View {
    /// 表示する説明の内容です。
    let content: LiveTelemetryPIDHelpContent
    /// シートを閉じる操作を通知するクロージャです。
    let onClose: () -> Void

    /// 説明の各行を節として並べ、閉じる操作を置きます。
    ///
    /// 責務: 1件のPID説明内容をナビゲーション見出し付きの一覧へ描画します。
    var body: some View {
        NavigationStack {
            List {
                ForEach(content.rows) { row in
                    Section(LocalizedStringKey(row.titleKey)) {
                        Text(LocalizedStringKey(row.bodyKey))
                    }
                }
            }
            .navigationTitle(LocalizedStringKey(content.titleKey))
            .toolbar {
                Button("common.close", action: onClose)
            }
        }
    }
}
#endif
