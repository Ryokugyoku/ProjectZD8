#if os(iOS)
import SwiftUI

/// データベースを開けなかった時に表示する、操作のない全画面のエラー画面です。
struct IOSLaunchFailureView: View {
    private let message: Text

    /// 責務: 失敗の説明文を受け取ります。
    /// - Parameter message: 呼び出し側がローカライズした失敗の説明。
    init(message: Text) {
        self.message = message
    }

    var body: some View {
        EmptyStateView(
            symbol: "exclamationmark.triangle.fill",
            title: Text("launch.failure.title"),
            message: message
        )
        .padding(InsightSpacing.screenGutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(InsightBackground())
    }
}
#endif
