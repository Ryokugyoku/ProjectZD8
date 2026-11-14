#if os(macOS)
import SwiftUI

/// macOS向けに進行中セッションと車両別アーカイブをコックピット調で描画します。
struct MacOSConnectionHistoryView: View {
    /// 接続履歴内の車両一覧とセッション詳細を結ぶ一時的な画面遷移経路です。
    @State private var navigationState = MacOSConnectionHistoryNavigationState()

    /// LogHistoryが提供する現在の履歴状態です。
    let state: ConnectionHistoryState
    /// 履歴の型付き操作をApplicationへ通知します。
    let send: (ConnectionHistoryAction) -> Void
    /// 現在表示中のPID時系列解析状態です。
    let analysisState: SessionLogAnalysisState
    /// PID時系列解析操作をApplicationへ通知します。
    let sendAnalysis: (SessionLogAnalysisAction) -> Void
    /// 現在のウインドウサイズに対応する表示寸法です。
    let metrics: MacOSAppShellMetrics

    /// macOSの alert 構成です。アップロード失敗には再試行ボタンを置きません。
    private let alertFactory = ConnectionHistoryAlertFactory()
    /// alert 本文のRaw件数と容量を整形します。
    private let rawSummaryFormatter = ConnectionHistoryRawSummaryMessageFormatter()

    /// macOS向けの階層化された接続履歴と詳細導線を提供します。
    ///
    /// 責務: 接続履歴の部品配置、画面遷移、alert をルート画面へ接続します。
    var body: some View {
        NavigationStack(path: $navigationState.path) {
            ScrollView {
                content.padding(26 * metrics.scale)
            }
            .background(MacOSConnectionHistoryBackground(scale: metrics.scale))
            .navigationDestination(for: MacOSConnectionHistoryRoute.self, destination: destination)
            .accessibilityIdentifier("macos-connection-history")
        }
        .onAppear { send(.refreshRequested) }
        .onChange(of: Set(state.sessions.map(\.id))) { _, availableSessionIDs in
            navigationState.returnFromDeletedSession(availableSessionIDs: availableSessionIDs)
        }
        .actionAlerts(
            ConnectionHistoryAlertKind.allCases.map { alertFactory.alert($0, in: state) },
            send: send,
            message: alertMessage
        )
    }

    /// 履歴状態に応じたヒーロー、失敗、空、進行中、アーカイブの配置です。
    private var content: some View {
        VStack(alignment: .leading, spacing: 20 * metrics.scale) {
            MacOSConnectionHistoryHeroCard(
                sessionCount: state.sessions.count,
                totalRecordedDuration: state.totalRecordedDuration,
                scale: metrics.scale
            )
            if state.phase == .failed {
                MacOSConnectionHistoryFailureState(scale: metrics.scale) { send(.refreshRequested) }
            } else if state.sessions.isEmpty {
                MacOSConnectionHistoryEmptyState(scale: metrics.scale)
            } else {
                MacOSConnectionHistoryActiveSection(sessions: state.activeSessions, scale: metrics.scale)
                MacOSConnectionHistoryArchiveSection(groups: state.vehicleGroups, scale: metrics.scale)
            }
        }
    }

    /// 接続履歴内の遷移先画面を返します。
    ///
    /// 責務: 1件の遷移経路を車両別セッション一覧またはセッション詳細の画面へ変換します。
    /// - Parameter route: 表示する遷移経路。
    /// - Returns: 遷移先の画面。対象セッションが見つからない場合は空。
    @ViewBuilder private func destination(_ route: MacOSConnectionHistoryRoute) -> some View {
        switch route {
        case let .vehicleSessions(id):
            MacOSConnectionHistoryVehicleSessionsView(
                groupID: id,
                state: state,
                send: send,
                metrics: metrics,
                back: { navigationState.returnToVehicleArchive() }
            )
        case let .sessionDetail(id):
            if let session = state.sessions.first(where: { $0.id == id }) {
                MacOSConnectionSessionDetailView(
                    session: session,
                    metrics: metrics,
                    send: send,
                    analysisState: analysisState,
                    sendAnalysis: sendAnalysis,
                    isDeleting: state.deletingSessionID == session.id,
                    back: { navigationState.returnToVehicleSessionList() }
                )
            }
        }
    }

    /// alert 本文の表示元を `Text` へ変換します。
    ///
    /// 責務: 1件の alert 本文をローカライズ文言またはRaw集計入りの警告文へ変換します。
    /// - Parameter message: Applicationが準備した alert 本文。
    /// - Returns: alert に表示する本文。
    private func alertMessage(_ message: ConnectionHistoryAlertMessage) -> Text {
        switch message {
        case let .localized(key):
            Text(LocalizedStringKey(key))
        case let .rawSummary(formatKey, recordCount, byteCount):
            Text(rawSummaryFormatter.text(formatKey: formatKey, recordCount: recordCount, byteCount: byteCount))
        }
    }
}
#endif
