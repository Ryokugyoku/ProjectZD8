#if os(macOS)
import SwiftUI

/// 選択車両の絞り込み可能な終了済みセッション一覧画面です。
struct MacOSConnectionHistoryVehicleSessionsView: View {
    /// 表示する車両グループ識別子です。
    let groupID: ConnectionHistoryVehicleGroupID
    /// LogHistoryが提供する現在の履歴状態です。
    let state: ConnectionHistoryState
    /// 履歴の型付き操作をApplicationへ通知します。
    let send: (ConnectionHistoryAction) -> Void
    /// 現在のウインドウサイズに対応する表示寸法です。
    let metrics: MacOSAppShellMetrics
    /// 車両別アーカイブへ戻る操作です。
    let back: () -> Void

    /// 容量解放の表示条件です。手動アップロードの表示条件は `state.isManualUploadAvailable` に従います。
    private let actionPolicy = ConnectionHistorySessionActionPolicy()

    /// 固定ヘッダーとその下でスクロールする絞り込み・一覧を描画します。
    ///
    /// 責務: 1台分の履歴へ複合絞り込みと並び替えを適用したデスクトップ一覧を配置します。
    var body: some View {
        let group = state.vehicleGroups.first(where: { $0.id == groupID })
        let sessions = state.filteredSessions(for: groupID)
        // 戻る操作と車両情報のヘッダーバナーは固定し、その下だけをスクロールさせる。
        VStack(alignment: .leading, spacing: 0) {
            MacOSConnectionHistoryVehicleSessionsHeader(group: group, scale: metrics.scale, back: back)
                .padding([.horizontal, .top], 28 * metrics.scale)
                .padding(.bottom, 18 * metrics.scale)
            scrollContent(sessions)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(MacOSConnectionHistoryBackground(scale: metrics.scale))
        .navigationBarBackButtonHidden(true)
    }

    /// 固定ヘッダーの下でスクロールする絞り込みとセッション一覧を描画します。
    ///
    /// 責務: 絞り込み済みセッション列を絞り込みパネルと一覧のスクロール領域へ配置します。
    /// - Parameter sessions: 表示する絞り込み済みセッション。
    /// - Returns: 絞り込みパネルとセッション一覧を含むスクロール領域。
    private func scrollContent(_ sessions: [ConnectionSession]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18 * metrics.scale) {
                MacOSConnectionHistoryVehicleSessionsFilterPanel(state: state, send: send, scale: metrics.scale)
                if sessions.isEmpty {
                    MacOSConnectionHistoryVehicleSessionsNoResults(scale: metrics.scale)
                } else {
                    LazyVStack(spacing: 10 * metrics.scale) {
                        ForEach(sessions) { session in
                            MacOSConnectionHistoryVehicleSessionsListItem(
                                session: session,
                                canUpload: state.isManualUploadAvailable(for: session),
                                canReleaseRawCache: actionPolicy.canReleaseRawCache(session),
                                uploadingSessionID: state.uploadingSessionID,
                                uploadProgress: state.uploadProgress,
                                scale: metrics.scale,
                                send: send
                            )
                        }
                    }
                }
            }
            .padding([.horizontal, .bottom], 28 * metrics.scale)
        }
    }
}
#endif
