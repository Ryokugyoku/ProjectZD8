#if os(iOS)
import SwiftUI

/// 選択車両の絞り込み可能な終了済みセッション一覧画面です。
struct IOSConnectionHistoryVehicleSessionsView: View {
    /// 表示する車両グループ識別子です。
    let groupID: ConnectionHistoryVehicleGroupID
    /// LogHistoryが提供する現在の履歴状態です。
    let state: ConnectionHistoryState
    /// 履歴の型付き操作をApplicationへ通知します。
    let send: (ConnectionHistoryAction) -> Void

    /// 車両グループ名を整形します。
    private let textFormatter = ConnectionHistorySessionTextFormatter()
    /// 容量解放の表示条件です。手動アップロードの表示条件は `state.isManualUploadAvailable` に従います。
    private let actionPolicy = ConnectionHistorySessionActionPolicy()

    /// 概要、絞り込み、セッション一覧を縦にスクロールさせて描画します。
    ///
    /// 責務: 1台分の履歴へ複合絞り込みと並び替えを適用した一覧を配置します。
    var body: some View {
        let group = state.vehicleGroups.first(where: { $0.id == groupID })
        let sessions = state.filteredSessions(for: groupID)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                IOSConnectionHistoryVehicleSessionsHeader(group: group)
                IOSConnectionHistoryVehicleSessionsFilterPanel(state: state, send: send)
                if sessions.isEmpty { IOSConnectionHistoryVehicleSessionsNoResults() } else {
                    ForEach(sessions) { session in listItem(session) }
                }
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .navigationTitle(textFormatter.vehicleGroupName(group?.vehicle))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// 1件のセッションの一覧項目を返します。
    ///
    /// 責務: 1件のセッションへ、履歴状態から決まる操作の表示条件と送信状態を渡します。
    /// - Parameter session: 表示する終了済みセッション。
    /// - Returns: 詳細導線と保管操作を含む一覧項目。
    private func listItem(_ session: ConnectionSession) -> some View {
        IOSConnectionHistoryVehicleSessionsListItem(
            session: session,
            canUpload: state.isManualUploadAvailable(for: session),
            canReleaseRawCache: actionPolicy.canReleaseRawCache(session),
            uploadingSessionID: state.uploadingSessionID,
            uploadProgress: state.uploadProgress,
            send: send
        )
    }
}
#endif
