#if os(iOS)
import SwiftUI

/// iPhone向けに選択セッションのRawログ端末・CloudKit保管状態を描画します。
struct IOSConnectionSessionDetailView: View {
    /// 表示対象の接続セッションです。
    let session: ConnectionSession
    /// LogHistoryの型付き操作をApplicationへ通知します。
    let send: (ConnectionHistoryAction) -> Void
    /// 現在表示中のPID時系列解析状態です。
    let analysisState: SessionLogAnalysisState
    /// PID時系列解析操作をApplicationへ通知します。
    let sendAnalysis: (SessionLogAnalysisAction) -> Void
    /// 走行ルート(地図)の表示状態です。
    let drivingRouteState: DrivingRouteDetailState
    /// 走行ルートの操作をApplicationへ通知します。
    let sendDrivingRoute: (DrivingRouteDetailAction) -> Void
    /// PID解析画面の走行ルート(色分けとグラフ連動)の表示状態です。
    let routeAnalysisState: RouteAnalysisState
    /// 解析画面の走行ルートの操作をApplicationへ通知します。
    let sendRouteAnalysis: (RouteAnalysisAction) -> Void
    /// PID解析画面の交通規制の照合の表示状態です。
    let roadRegulationReviewState: SessionRoadRegulationReviewState
    /// 解析画面の交通規制の照合の操作をApplicationへ通知します。
    let sendRoadRegulationReview: (SessionRoadRegulationReviewAction) -> Void
    /// 表示対象をiCloudを含めて削除している途中かを示します。
    let isDeleting: Bool
    /// PID時系列解析画面を表示しているかを示す一時的なナビゲーション状態です。
    @State private var isAnalysisPresented = false
    /// 大きく表示している走行ルートの地図の内容です。表示していない時は `nil` です。
    ///
    /// 画面全体の表示中に下の画面の表示が外れて状態が変わっても、開いた時の内容を描き続けるために保持します。
    @State private var expandedRouteContent: DrivingRouteMapContent?
    /// 詳細画面の判定・整形・文言キーの選択です。
    private let formatter = ConnectionSessionDetailTextFormatter()

    /// Rawログの来歴と安全なローカル除去導線を提供します。
    ///
    /// 責務: 1件の接続セッションをiPhoneとCloudKitの保管状態へ分けて描画します。
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                IOSConnectionSessionDetailActions(
                    canDelete: session.endedAt != nil,
                    isDeleting: isDeleting,
                    onDelete: { send(.sessionDeletionRequested(session.id)) }
                )
                IOSConnectionSessionDetailHero(
                    session: session,
                    acquisitionDeviceText: formatter.acquisitionDeviceText(session)
                )
                IOSConnectionSessionDetailStopReviewCard(
                    needsStopReview: session.needsStopReview,
                    isUserAccepted: session.stopReviewDecision == .userInitiated,
                    messageKey: formatter.stopReviewMessageKey(session),
                    onReview: { send(.stopReviewRequested(session.id)) }
                )
                IOSConnectionSessionDetailRouteCard(
                    phase: drivingRouteState.phase,
                    onExpand: { expandedRouteContent = $0 },
                    onRetry: { sendDrivingRoute(.retryRequested) }
                )
                IOSConnectionSessionDetailRawMetrics(
                    recordCountText: session.rawLogSummary.recordCount.formatted(),
                    byteCountText: formatter.byteCountText(session.rawLogSummary.byteCount)
                )
                IOSConnectionSessionDetailStorageJourney(
                    localState: session.rawLogSummary.localState,
                    cloudState: session.rawLogSummary.cloudState
                )
                IOSConnectionSessionDetailAnalysisButton(onOpen: openAnalysis)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .background(background)
        .navigationTitle("history.detail.title")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $isAnalysisPresented) {
            IOSSessionLogAnalysisView(
                session: session,
                state: analysisState,
                send: sendAnalysis,
                routeAnalysisState: routeAnalysisState,
                sendRouteAnalysis: sendRouteAnalysis,
                roadRegulationReviewState: roadRegulationReviewState,
                sendRoadRegulationReview: sendRoadRegulationReview
            )
        }
        .fullScreenCover(isPresented: isRouteMapExpanded) {
            if let expandedRouteContent {
                IOSConnectionSessionDetailRouteMapSheet(content: expandedRouteContent, onClose: { self.expandedRouteContent = nil })
            }
        }
        .task(id: session.id) { sendDrivingRoute(.sessionShown(session)) }
        .onDisappear { sendDrivingRoute(.sessionHidden(session.id)) }
        .alert(
            "analysis.download.confirm.title",
            isPresented: Binding(
                get: { analysisState.downloadPrompt?.sessionID == session.id },
                set: { if !$0 { sendAnalysis(.downloadCancelled) } }
            ),
            presenting: analysisState.downloadPrompt
        ) { _ in
            Button("analysis.download.cancel", role: .cancel) {
                sendAnalysis(.downloadCancelled)
            }
            Button("analysis.download.confirm") {
                sendAnalysis(.downloadConfirmed)
                isAnalysisPresented = true
            }
        } message: { prompt in
            Text(downloadConfirmationMessage(prompt))
        }
        .accessibilityIdentifier("ios-connection-session-detail")
    }

    /// 解析の対象を選び、ローカルにRawログが残っていれば解析画面を開きます。
    ///
    /// 責務: 解析の選択を送出し、ローカルのRawログが除去済みでない時だけ解析画面への遷移状態を立てます。
    private func openAnalysis() {
        sendAnalysis(.sessionSelected(session))
        if session.rawLogSummary.localState != .removed {
            isAnalysisPresented = true
        }
    }

    /// 走行ルートの地図を画面全体に表示しているかの束縛です。
    ///
    /// 責務: 保持している地図の内容の有無を表示の可否とし、閉じられた時に内容を捨てます。
    private var isRouteMapExpanded: Binding<Bool> {
        Binding(
            get: { expandedRouteContent != nil },
            set: { if !$0 { expandedRouteContent = nil } }
        )
    }

    /// iCloud取得確認用に予定容量を含む本文を返します。
    ///
    /// 責務: 1件のRaw取得確認情報をローカライズ済み容量付き本文へ変換します。
    /// - Parameter prompt: 取得対象IDと予定バイト数を保持する確認情報。
    /// - Returns: 現在Locale向けの容量を含む確認本文。
    private func downloadConfirmationMessage(_ prompt: SessionLogAnalysisState.DownloadPrompt) -> String {
        String(
            format: String(localized: "analysis.download.confirm.message"),
            formatter.byteCountText(prompt.byteCount)
        )
    }

    /// iPhone詳細画面へ奥行きを与える背景です。
    private var background: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
            RadialGradient(colors: [Color.blue.opacity(0.08), .clear], center: .topTrailing, startRadius: 0, endRadius: 480)
        }
        .ignoresSafeArea()
    }
}
#endif
