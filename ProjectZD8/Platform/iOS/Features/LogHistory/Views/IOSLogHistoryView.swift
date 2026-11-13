#if os(iOS)
import SwiftUI

/// ログタブの入口です。モデルの状態を読み、操作を送るだけで何も所有しません。
struct IOSLogHistoryView: View {
    let logHistory: LogHistoryModel

    var body: some View {
        IOSLogHistoryScreen(state: logHistory.state) { logHistory.send($0) }
    }
}
#endif
