#if os(iOS)
import SwiftUI

/// iPhone向けに保存済みPIDログを走行サマリー、グラフ、Raw根拠へ整理します。
struct IOSSessionLogAnalysisView: View {
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
    /// 現在選択中の解析表示です。
    @State private var mode: SessionLogAnalysisMode = .overview
    /// 折れ線グラフへ表示するPIDです。
    @State private var selectedSeriesID: OBDPIDRequest?
    /// 散布図へ表示するPID組です。
    @State private var selectedRelationshipID: String?
    /// 交通規制の照合の行を選ぶたびに増やし、走行ルートの表示へのスクロールを要求する番号です。
    @State private var routeScrollRequest = 0
    /// スクロールで戻る先の、走行ルートの表示の識別子です。
    private static let routeScrollID = "ios-analysis-route-scroll-target"
    /// 読込段階から本文の内容を決める判定です。
    private let contentPolicy = SessionLogAnalysisContentPolicy()
    /// 走行ルートと解析の読込段階から、交通規制の照合を始められるかを決める判定です。
    private let reviewReadinessResolver = SessionRoadRegulationReviewReadinessResolver()

    /// 接続履歴と同じ視覚階層でセッション解析を提供します。
    ///
    /// 責務: 1件のセッション解析状態をiPhone向け走行サマリーとグラフへ変換します。
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    IOSSessionLogAnalysisHero(session: session)
                    IOSSessionLogAnalysisSummary(
                        sampleCount: state.timeline.count,
                        decodedCount: state.decodedSampleCount,
                        rawOnlyCount: state.rawOnlySampleCount
                    )
                    modePicker
                    selectedContent
                }
                .padding(20)
            }
            .onChange(of: routeScrollRequest) { _, _ in
                withAnimation { proxy.scrollTo(Self.routeScrollID, anchor: .top) }
            }
        }
        .background(background)
        .navigationTitle("analysis.title")
        .navigationBarTitleDisplayMode(.inline)
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
        .onDisappear {
            send(.dismissed)
            sendRouteAnalysis(.dismissed)
            sendRoadRegulationReview(.dismissed)
        }
        .onChange(of: state.pidSeries.map(\.id)) { _, _ in selectDefaults() }
        .onChange(of: state.relationships.map(\.id)) { _, _ in selectDefaults() }
        .accessibilityIdentifier("ios-session-log-analysis")
    }

    /// 解析の表示モードをメニューとして切り替えます。
    private var modePicker: some View {
        Picker("analysis.mode.title", selection: $mode) {
            ForEach(SessionLogAnalysisMode.allCases) { item in
                Text(LocalizedStringKey(item.titleKey)).tag(item)
            }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("ios-analysis-mode")
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
            IOSSessionLogAnalysisDownloadProgress(progress: progress)
        case .initialLoading:
            ProgressView("analysis.loading").frame(maxWidth: .infinity).padding(28)
        case .failedWithoutData:
            failure
        case .empty:
            ContentUnavailableView("analysis.empty.title", systemImage: "waveform.slash", description: Text("analysis.empty.body"))
        case .results(let showsProgress):
            if showsProgress {
                IOSSessionLogAnalysisLoadingProgress(loadedCount: state.timeline.count, totalCount: state.totalSampleCount)
            }
            modeContent
        }
    }

    /// 選択中の表示モードの解析結果を描画します。
    @ViewBuilder private var modeContent: some View {
        switch mode {
        case .overview:
            IOSSessionLogAnalysisOverview(
                session: session,
                summary: state.performanceSummary,
                componentInsights: state.componentInsights
            )
        case .trends:
            IOSSessionLogAnalysisTrendCard(seriesList: state.pidSeries, selectedSeriesID: $selectedSeriesID)
        case .relationships:
            IOSSessionLogAnalysisRelationshipCard(
                relationships: state.relationships,
                selectedRelationshipID: $selectedRelationshipID
            )
        case .route:
            IOSSessionLogAnalysisRouteSection(session: session, state: routeAnalysisState, send: sendRouteAnalysis)
                .id(Self.routeScrollID)
            IOSSessionLogAnalysisRoadRegulationSection(
                state: roadRegulationReviewState,
                onFilterChanged: { sendRoadRegulationReview(.filterChanged($0)) },
                onRowSelected: selectRoadRegulationRow,
                onRetry: { sendRoadRegulationReview(.retryRequested) }
            )
        }
    }

    /// 時系列が無いまま読込に失敗したことを示します。
    private var failure: some View {
        HStack(spacing: 9) {
            WarningTriangleIcon(size: 18, color: .red)
            Text("analysis.error.storage")
        }
        .foregroundStyle(.red)
        .padding(20)
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

    /// 交通規制の照合の行の選択を送出し、その区間を走行ルートの表示で示します。
    ///
    /// 責務: 行の選択を照合へ、その種類の重ね合わせの色分けを走行ルートへこの順で送出し、
    /// 新たに選んだ時だけ(選択の解除では動かさず)走行ルートの表示へスクロールを要求します。
    /// - Parameter row: 選ばれた行。
    private func selectRoadRegulationRow(_ row: SessionRoadRegulationReviewRow) {
        let isDeselecting = roadRegulationReviewState.selectedRowID == row.id
        sendRoadRegulationReview(.rowSelected(row.id))
        sendRouteAnalysis(.colorSourceSelected(.overlay(id: row.overlayID)))
        if !isDeselecting { routeScrollRequest += 1 }
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
            Color(uiColor: .systemGroupedBackground)
            RadialGradient(colors: [Color.accentColor.opacity(0.08), .clear], center: .topTrailing, startRadius: 0, endRadius: 480)
        }
        .ignoresSafeArea()
    }
}
#endif
