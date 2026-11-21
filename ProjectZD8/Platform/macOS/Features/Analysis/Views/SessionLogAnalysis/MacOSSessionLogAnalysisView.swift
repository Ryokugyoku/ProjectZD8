#if os(macOS)
import SwiftUI

/// macOS向けに保存済みPIDログを走行サマリー、グラフ、Raw根拠へ整理します。
struct MacOSSessionLogAnalysisView: View {
    /// 表示するセッションです。
    let session: ConnectionSession
    /// Analysisが提供する時系列解析状態です。
    let state: SessionLogAnalysisState
    /// Analysisの型付き操作をApplicationへ通知します。
    let send: (SessionLogAnalysisAction) -> Void
    /// 走行ルート(色分けとグラフ連動)の表示状態です。
    let routeAnalysisState: RouteAnalysisState
    /// 走行ルートの型付き操作をApplicationへ通知します。
    let sendRouteAnalysis: (RouteAnalysisAction) -> Void
    /// 交通規制の照合の表示状態です。
    let roadRegulationReviewState: SessionRoadRegulationReviewState
    /// 交通規制の照合の型付き操作をApplicationへ通知します。
    let sendRoadRegulationReview: (SessionRoadRegulationReviewAction) -> Void
    /// 現在のウインドウ寸法に対応する表示寸法です。
    let metrics: MacOSAppShellMetrics
    /// 現在選択中の解析表示です。
    @State private var mode: SessionLogAnalysisMode = .overview
    /// 折れ線グラフへ表示するPIDです。
    @State private var selectedSeriesID: OBDPIDRequest?
    /// 散布図へ表示するPID組です。
    @State private var selectedRelationshipID: String?
    /// 走行ルートの表示へスクロールする依頼の回数です。交通規制の行を選ぶたびに増やします。
    @State private var routeScrollRequest = 0
    /// NavigationStackの直前画面へ戻す環境操作です。
    @Environment(\.dismiss) private var dismiss
    /// 読込段階から本文の内容を決める判定です。
    private let contentPolicy = SessionLogAnalysisContentPolicy()
    /// 走行ルートと解析の読込段階から、交通規制の照合を始められるかを決める判定です。
    private let reviewReadinessResolver = SessionRoadRegulationReviewReadinessResolver()
    /// 交通規制の行を選んだ時にスクロールして見せる、走行ルートの表示の識別子です。
    private static let routeScrollID = "macos-analysis-route-scroll-target"

    /// 接続履歴と同じ視覚階層でセッション解析を提供します。
    ///
    /// 責務: 1件のセッション解析状態をmacOS向け走行サマリーとグラフへ変換します。
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20 * metrics.scale) {
                    navigationBar
                    MacOSSessionLogAnalysisHero(session: session, metrics: metrics)
                    MacOSSessionLogAnalysisSummary(
                        sampleCount: state.timeline.count,
                        decodedCount: state.decodedSampleCount,
                        rawOnlyCount: state.rawOnlySampleCount,
                        metrics: metrics
                    )
                    modePicker
                    selectedContent
                }
                .padding(28 * metrics.scale)
                .frame(maxWidth: 1_180 * metrics.scale)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .onChange(of: routeScrollRequest) { _, _ in
                withAnimation { proxy.scrollTo(Self.routeScrollID, anchor: .top) }
            }
        }
        .background(background)
        .navigationTitle("analysis.title")
        .navigationBarBackButtonHidden(true)
        .onAppear {
            if state.sessionID != session.id { send(.sessionSelected(session)) }
            selectDefaults()
            reportLoadedTimeline()
        }
        .onChange(of: state.phase) { _, _ in reportLoadedTimeline() }
        .onChange(of: reviewReadiness, initial: true) { _, readiness in
            sendRoadRegulationReview(.readinessChanged(session.id, readiness))
        }
        .onChange(of: roadRegulationReviewState.overlays) { _, overlays in sendRouteAnalysis(.overlaysChanged(overlays)) }
        .onChange(of: state.pidSeries.map(\.id)) { _, _ in selectDefaults() }
        .onChange(of: state.relationships.map(\.id)) { _, _ in selectDefaults() }
        .accessibilityIdentifier("macos-session-log-analysis")
    }

    /// セッション詳細へ戻る操作を表示します。
    private var navigationBar: some View {
        HStack {
            RoundedBackButton(
                accessibilityLabelKey: "analysis.back.session",
                identifier: "macos-analysis-session-back",
                scale: metrics.scale
            ) {
                send(.dismissed)
                sendRouteAnalysis(.dismissed)
                sendRoadRegulationReview(.dismissed)
                dismiss()
            }
            Spacer()
        }
    }

    /// 解析の表示モードを明示的に切り替えます。
    private var modePicker: some View {
        Picker("analysis.mode.title", selection: $mode) {
            ForEach(SessionLogAnalysisMode.allCases) { item in
                Text(LocalizedStringKey(item.titleKey)).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("macos-analysis-mode")
    }

    /// 選択中の表示モードと読込段階に対応する本文を描画します。
    ///
    /// 責務: 「ルート」は時系列の読込段階に関係なく表示し(Raw の読込に失敗してもルートと標高は出せます)、
    /// それ以外のモードは時系列の読込段階に応じて描画します。
    @ViewBuilder private var selectedContent: some View {
        if mode == .route {
            modeContent
        } else {
            timelineContent
        }
    }

    /// 時系列の読込段階に対応する本文を描画します。
    @ViewBuilder private var timelineContent: some View {
        switch contentPolicy.content(for: state) {
        case .downloading(let progress):
            MacOSSessionLogAnalysisDownloadProgress(progress: progress, metrics: metrics)
        case .initialLoading:
            ProgressView("analysis.loading").frame(maxWidth: .infinity).padding(40 * metrics.scale)
        case .failedWithoutData:
            failure
        case .empty:
            ContentUnavailableView("analysis.empty.title", systemImage: "waveform.slash", description: Text("analysis.empty.body"))
        case .results(let showsProgress):
            if showsProgress {
                MacOSSessionLogAnalysisLoadingProgress(loadedCount: state.timeline.count, totalCount: state.totalSampleCount)
            }
            modeContent
        }
    }

    /// 選択中の表示モードの解析結果を描画します。
    @ViewBuilder private var modeContent: some View {
        switch mode {
        case .overview:
            MacOSSessionLogAnalysisOverview(
                session: session,
                summary: state.performanceSummary,
                componentInsights: state.componentInsights,
                metrics: metrics
            )
        case .trends:
            MacOSSessionLogAnalysisTrendCard(seriesList: state.pidSeries, selectedSeriesID: $selectedSeriesID, metrics: metrics)
        case .relationships:
            MacOSSessionLogAnalysisRelationshipCard(
                relationships: state.relationships,
                selectedRelationshipID: $selectedRelationshipID,
                metrics: metrics
            )
        case .route:
            MacOSSessionLogAnalysisRouteSection(session: session, state: routeAnalysisState, metrics: metrics, send: sendRouteAnalysis)
                .id(Self.routeScrollID)
            MacOSSessionLogAnalysisRoadRegulationSection(
                state: roadRegulationReviewState,
                metrics: metrics,
                send: sendRoadRegulationReview,
                onSelectRow: selectRoadRegulationRow
            )
        }
    }

    /// 交通規制の行を選んだ操作を送出し、走行ルートの表示へスクロールします。
    ///
    /// 責務: 行の選択(同じ行なら解除)を送り、選ぶ時だけ段階4の色分けをその種類の重ね合わせに切り替えてルートの表示へスクロールします。
    /// - Parameter row: 選んだ行。
    private func selectRoadRegulationRow(_ row: SessionRoadRegulationReviewRow) {
        let isDeselecting = roadRegulationReviewState.selectedRowID == row.id
        sendRoadRegulationReview(.rowSelected(row.id))
        guard !isDeselecting else { return }
        sendRouteAnalysis(.colorSourceSelected(.overlay(id: row.overlayID)))
        routeScrollRequest += 1
    }

    /// 時系列が無いまま読込に失敗したことを示します。
    private var failure: some View {
        HStack(spacing: 10 * metrics.scale) {
            WarningTriangleIcon(size: 18 * metrics.scale, color: .red)
            Text("analysis.error.storage")
        }
        .foregroundStyle(.red)
    }

    /// 走行ルートと解析の読込段階から決めた、交通規制の照合を始められるかの段階です。
    ///
    /// 別のセッションの状態が残っている間は、そのセッションの段階で照合を始めないよう待ちの段階になります。
    private var reviewReadiness: SessionRoadRegulationReviewReadiness {
        reviewReadinessResolver.readiness(
            for: session.id,
            routeSessionID: routeAnalysisState.sessionID,
            routePhase: routeAnalysisState.phase,
            analysisSessionID: state.sessionID,
            analysisPhase: state.phase
        )
    }

    /// 時系列を読み終えていれば、走行ルートのモデルへ渡します。
    ///
    /// 責務: 表示中のセッションの時系列が `loaded` の時だけ、`timelineLoaded` を走行ルートの操作として送出します。
    private func reportLoadedTimeline() {
        guard state.phase == .loaded, state.sessionID == session.id else { return }
        sendRouteAnalysis(.timelineLoaded(session.id, state.timeline))
    }

    /// 読込済み系列から未選択の折れ線と散布図へ初期値を設定します。
    ///
    /// 責務: 現在の解析系列を未選択Pickerの先頭選択へ反映します。
    private func selectDefaults() {
        if selectedSeriesID == nil { selectedSeriesID = state.pidSeries.first?.id }
        if selectedRelationshipID == nil { selectedRelationshipID = state.relationships.first?.id }
    }

    /// 接続履歴画面と同じ抑制された奥行きを与える背景です。
    private var background: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            RadialGradient(
                colors: [Color.accentColor.opacity(0.075), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 620 * metrics.scale
            )
        }
    }
}
#endif
