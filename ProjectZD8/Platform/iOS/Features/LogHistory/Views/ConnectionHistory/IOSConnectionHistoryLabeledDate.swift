#if os(iOS)
import SwiftUI

/// 日時を短い見出しとともに示す、履歴カード用の表示です。
struct IOSConnectionHistoryLabeledDate: View {
    /// 日時の意味を示すローカライズキーです。
    let titleKey: LocalizedStringKey
    /// 表示する日時です。
    let date: Date

    /// 見出しと日時を縦に並べます。
    ///
    /// 責務: 1件の日時を履歴カード用の見出し付き表示へ配置します。
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(titleKey).font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
            Text(date, format: .dateTime.month().day().hour().minute()).font(.caption.monospacedDigit().weight(.semibold))
        }
    }
}
#endif
