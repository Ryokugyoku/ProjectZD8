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
    /// 現在選択中の解析表示です。
    @State private var mode: SessionLogAnalysisMode = .overview
    /// 折れ線グラフへ表示するPIDです。
    @State private var selectedSeriesID: OBDPIDRequest?
    /// 散布図へ表示するPID組です。
    @State private var selectedRelationshipID: String?
    /// 読込段階から本文の内容を決める判定です。
    private let contentPolicy = SessionLogAnalysisContentPolicy()

    /// 接続履歴と同じ視覚階層でセッション解析を提供します。
    ///
    /// 責務: 1件のセッション解析状態をiPhone向け走行サマリーとグラフへ変換します。
    var body: some View {
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
        .background(background)
        .navigationTitle("analysis.title")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if state.sessionID != session.id { send(.sessionSelected(session)) }
            selectDefaults()
        }
        .onDisappear { send(.dismissed) }
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

    /// 現在の読込段階に対応する本文を描画します。
    @ViewBuilder private var selectedContent: some View {
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
