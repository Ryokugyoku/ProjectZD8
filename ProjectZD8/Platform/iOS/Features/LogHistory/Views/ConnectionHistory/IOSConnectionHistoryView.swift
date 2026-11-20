#if os(iOS)
import SwiftUI

/// iPhone向けに進行中セッションと車両別アーカイブを描画します。
struct IOSConnectionHistoryView: View {
    /// LogHistoryが提供する現在の履歴状態です。
    let state: ConnectionHistoryState
    /// 履歴の型付き操作をApplicationへ通知します。
    let send: (ConnectionHistoryAction) -> Void

    /// 現在表示中のPID時系列解析状態です。
    let analysisState: SessionLogAnalysisState
    /// PID時系列解析操作をApplicationへ通知します。
    let sendAnalysis: (SessionLogAnalysisAction) -> Void

    /// iOSの alert 構成です。アップロード失敗には再試行ボタンを置きます。
    private let alertFactory = ConnectionHistoryAlertFactory()
    /// alert 本文のRaw件数と容量を整形します。
    private let rawSummaryFormatter = ConnectionHistoryRawSummaryMessageFormatter()

    /// iPhone向けの階層化された接続履歴と詳細導線を提供します。
    ///
    /// 責務: 接続履歴の部品配置、画面遷移、alert をルート画面へ接続します。
    var body: some View {
        NavigationStack {
            ScrollView {
                content
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .navigationDestination(for: ConnectionHistoryVehicleGroupID.self) { id in
                IOSConnectionHistoryVehicleSessionsView(groupID: id, state: state, send: send)
            }
            .navigationDestination(for: ConnectionSessionID.self, destination: sessionDetail)
            .refreshable { send(.refreshRequested) }
            .accessibilityIdentifier("ios-connection-history")
        }
        .actionAlerts(
            ConnectionHistoryAlertKind.allCases.map { alertFactory.alert($0, in: state) },
            send: send,
            message: alertMessage
        )
    }

    /// 履歴状態に応じたヒーロー、失敗、空、進行中、アーカイブの配置です。
    private var content: some View {
        LazyVStack(alignment: .leading, spacing: 18) {
            IOSConnectionHistoryHeroCard(sessionCount: state.sessions.count, totalRecordedDuration: state.totalRecordedDuration)
            if state.phase == .failed {
                IOSConnectionHistoryFailureState { send(.refreshRequested) }
            } else if state.sessions.isEmpty {
                IOSConnectionHistoryEmptyState()
            } else {
                IOSConnectionHistoryActiveSection(sessions: state.activeSessions)
                IOSConnectionHistoryArchiveSection(groups: state.vehicleGroups)
            }
        }
    }

    /// セッション詳細の遷移先画面を返します。
    ///
    /// 責務: 1件のセッションIDを、該当するセッションの詳細画面へ変換します。
    /// - Parameter id: 表示するセッションの識別子。
    /// - Returns: セッション詳細画面。対象セッションが見つからない場合は空。
    @ViewBuilder private func sessionDetail(_ id: ConnectionSessionID) -> some View {
        if let session = state.sessions.first(where: { $0.id == id }) {
            IOSConnectionSessionDetailView(
                session: session,
                send: send,
                analysisState: analysisState,
                sendAnalysis: sendAnalysis,
                isDeleting: state.deletingSessionID == session.id
            )
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
