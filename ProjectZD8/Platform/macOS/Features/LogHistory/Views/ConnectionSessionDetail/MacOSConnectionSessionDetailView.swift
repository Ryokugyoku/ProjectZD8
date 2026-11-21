#if os(macOS)
import SwiftUI

/// macOS向けに選択セッションのRawログと学習準備状態を描画します。
struct MacOSConnectionSessionDetailView: View {
    /// 表示対象の接続セッションです。
    let session: ConnectionSession
    /// 現在のウインドウサイズに対応する表示寸法です。
    let metrics: MacOSAppShellMetrics
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
    /// 表示対象を全端末から削除している途中かを示します。
    let isDeleting: Bool
    /// 車両セッション一覧へ戻る一時的な画面遷移操作です。
    let back: () -> Void
    /// PID時系列解析画面を表示しているかを示す一時的なナビゲーション状態です。
    @State private var isAnalysisPresented = false
    /// 走行ルートの地図を大きく表示しているかを示す一時的な表示状態です。
    @State private var isRouteMapPresented = false
    /// 詳細画面の判定・整形・文言キーの選択です。
    private let formatter = ConnectionSessionDetailTextFormatter()

    /// 車両別学習データの来歴と保管状態を提供します。
    ///
    /// 責務: 1件の接続セッションをMac保管済みRawログと車両別学習準備へ分けて描画します。
    var body: some View {
        // 戻る・削除操作は固定し、詳細カードだけをスクロールさせる。
        VStack(alignment: .leading, spacing: 0) {
            MacOSConnectionSessionDetailActions(
                scale: metrics.scale,
                canDelete: session.endedAt != nil,
                isDeleting: isDeleting,
                onBack: back,
                onDelete: { send(.sessionDeletionRequested(session.id)) }
            )
            .padding([.horizontal, .top], 28 * metrics.scale)
            .padding(.bottom, 16 * metrics.scale)
            ScrollView {
                detailContent
                    .padding([.horizontal, .bottom], 28 * metrics.scale)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(MacOSConnectionSessionDetailBackground(scale: metrics.scale))
        .navigationTitle("history.detail.title")
        .navigationDestination(isPresented: $isAnalysisPresented) {
            MacOSSessionLogAnalysisView(
                session: session,
                state: analysisState,
                send: sendAnalysis,
                routeAnalysisState: routeAnalysisState,
                sendRouteAnalysis: sendRouteAnalysis,
                roadRegulationReviewState: roadRegulationReviewState,
                sendRoadRegulationReview: sendRoadRegulationReview,
                metrics: metrics
            )
        }
        .onChange(of: isAnalysisPresented) { wasPresented, isPresented in
            guard wasPresented, !isPresented else { return }
            send(.localDataChanged)
        }
        .sheet(isPresented: routeMapSheetBinding) {
            if let content = loadedRouteContent {
                MacOSConnectionSessionDetailRouteMapSheet(content: content, scale: metrics.scale) {
                    isRouteMapPresented = false
                }
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
        .accessibilityIdentifier("macos-connection-session-detail")
    }

    /// 固定した操作列の下でスクロールするセッション詳細カード群です。
    private var detailContent: some View {
        VStack(alignment: .leading, spacing: 20 * metrics.scale) {
            MacOSConnectionSessionDetailHero(
                session: session,
                scale: metrics.scale,
                acquisitionDeviceText: formatter.acquisitionDeviceText(session),
                statusKey: formatter.sessionStatusKey(session)
            )
            MacOSConnectionSessionDetailStopReviewCard(
                scale: metrics.scale,
                needsStopReview: session.needsStopReview,
                isUserAccepted: session.stopReviewDecision == .userInitiated,
                messageKey: formatter.stopReviewMessageKey(session),
                onReview: { send(.stopReviewRequested(session.id)) }
            )
            MacOSConnectionSessionDetailRouteCard(
                phase: drivingRouteState.phase,
                scale: metrics.scale,
                onExpand: { isRouteMapPresented = true },
                onRetry: { sendDrivingRoute(.retryRequested) }
            )
            HStack(alignment: .top, spacing: 16 * metrics.scale) {
                rawDataCard
                analysisCard
                integrityCard
            }
            MacOSConnectionSessionDetailTrainingCard(
                scale: metrics.scale,
                isTrainingReady: formatter.isTrainingReady(session),
                hasVehicle: session.vehicle != nil
            )
            MacOSConnectionSessionDetailLineageCard(scale: metrics.scale)
        }
    }

    /// 地図に描ける走行ルートの内容です。描ける段階でなければ `nil` です。
    private var loadedRouteContent: DrivingRouteMapContent? {
        guard case .loaded(let content) = drivingRouteState.phase else { return nil }
        return content
    }

    /// 地図を大きく表示するシートの表示状態です。描ける内容が無くなった時はシートを閉じた扱いにします。
    private var routeMapSheetBinding: Binding<Bool> {
        Binding(
            get: { isRouteMapPresented && loadedRouteContent != nil },
            set: { isRouteMapPresented = $0 }
        )
    }

    /// 未デコードRawログの件数と容量を表示します。
    private var rawDataCard: some View {
        MacOSConnectionSessionDetailStatusCard(
            scale: metrics.scale,
            titleKey: "history.training.raw.title",
            value: session.rawLogSummary.recordCount.formatted(),
            caption: formatter.byteCountText(session.rawLogSummary.byteCount),
            systemImage: "cylinder.split.1x2.fill",
            color: .cyan
        )
    }

    /// 車両スコープ枠を置き換える静的性能解析カードです。
    private var analysisCard: some View {
        Button(action: openAnalysis) {
            VStack(spacing: 8 * metrics.scale) {
                MacOSConnectionSessionDetailStatusCard(
                    scale: metrics.scale,
                    titleKey: "analysis.open",
                    value: String(localized: "analysis.card.value"),
                    caption: formatter.analysisCardCaption(session),
                    systemImage: "chart.xyaxis.line",
                    color: .indigo
                )
                HStack {
                    Text("analysis.open.hint")
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .font(.system(size: 10 * metrics.scale, weight: .bold))
                .foregroundStyle(.indigo)
                .padding(.horizontal, 4 * metrics.scale)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("macos-history-open-analysis")
    }

    /// ManifestとMac取込受領証の一致状態を表示します。
    private var integrityCard: some View {
        MacOSConnectionSessionDetailStatusCard(
            scale: metrics.scale,
            titleKey: "history.detail.disposition.title",
            value: formatter.dispositionText(session),
            caption: formatter.observedEndReasonText(session),
            systemImage: session.status == .completed ? "checkmark.shield.fill" : "shield.lefthalf.filled",
            color: session.status == .completed ? .green : .orange
        )
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
}
#endif
