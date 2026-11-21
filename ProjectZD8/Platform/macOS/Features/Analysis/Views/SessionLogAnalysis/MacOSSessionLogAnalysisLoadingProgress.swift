#if os(macOS)
import SwiftUI

/// macOSのセッション解析で逐次変換済み件数を全Rawログ件数に対する進捗として示します。
struct MacOSSessionLogAnalysisLoadingProgress: View {
    /// 変換済みの時系列件数です。
    let loadedCount: Int
    /// 全Rawログ件数です。未確定なら `nil` です。
    let totalCount: Int?

    /// 変換済み件数と全件数の進捗を表示します。
    ///
    /// 責務: 変換済み件数と全件数を、件数ラベル付きの進捗バーへ変換します。
    var body: some View {
        ProgressView(value: Double(loadedCount), total: Double(max(totalCount ?? loadedCount, 1))) {
            Text("analysis.loading")
        } currentValueLabel: {
            Text("\(loadedCount.formatted()) / \((totalCount ?? loadedCount).formatted())")
        }
        .font(.caption)
    }
}
#endif
