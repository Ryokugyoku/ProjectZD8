#if os(iOS)
import SwiftUI
import UIKit

/// 書き出したCSV・PNGのファイルを共有シートで渡します。
struct IOSAnalysisShareSheet: UIViewControllerRepresentable {
    let fileURL: URL
    let onFinish: () -> Void

    /// 責務: ファイルを共有するアクティビティ画面を作ります。完了時に一時ファイルを片付けます。
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            try? FileManager.default.removeItem(at: fileURL)
            onFinish()
        }
        return controller
    }

    /// 更新する内容はありません。
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
