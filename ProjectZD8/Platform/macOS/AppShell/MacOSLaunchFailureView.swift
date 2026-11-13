#if os(macOS)
import SwiftUI

/// データベースを開けない時に全画面で表示する、単純なエラー画面。
struct MacOSLaunchFailureView: View {
    let message: Text

    /// 責務: 失敗内容の文言を受け取って保持する。
    init(message: Text) {
        self.message = message
    }

    var body: some View {
        EmptyStateView(
            symbol: "exclamationmark.triangle.fill",
            title: Text("launch.failure.title"),
            message: message
        )
        .padding(InsightSpacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(InsightBackground())
        .frame(minWidth: 480, minHeight: 320)
    }
}
#endif
