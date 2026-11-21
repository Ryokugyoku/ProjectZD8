import Foundation
import Observation

/// 解析の走行ルートの表示(色分け・グラフ・グラフから地図への連動)の読み込みと状態を持ちます。
///
/// 型付きの Action を、走行ルートの読み込み(`RouteAnalysisTrackPort`)と状態の更新へ変換します。
/// - 読み込んだら、まず色なしの線と標高を出します。解析の時系列が届いていれば、時刻合わせ → 指標ごとの値の列 →
///   選択肢 → 既定の指標で色分け → 指標のグラフ、の順に作ります。時系列は読み込みの前に届いても、セッション ID と一緒に保持して使います。
/// - 作り直しはメインの外(`Task.detached`)で行い、世代の番号で古い結果を捨てます(別のセッションへ切り替えた後の結果で上書きしません)。
/// - 指標の PID がセッションに無い時は、その指標を選べません(GPS の速さなどでは代用しません)。選べない指標の選択は無視します。
/// - 重ね合わせ(5c の判定結果)は `overlaysChanged` で受け取り、選んだ時はその時刻の範囲を強調します。
/// - グラフ上の時刻の選択は、メインで二分探索するだけなので同期で処理します。
/// - 隔離はプロジェクト既定の MainActor です(既定の MainActor の `RouteAnalysisCursorResolver()` を既定引数で作るため、明示していません)。
@Observable
final class RouteAnalysisModel {
    /// 作り直しに渡す入力です。
    nonisolated private struct RebuildInput: Sendable {
        /// 読み込んだ走行ルートです。
        let route: DrivingRoute
        /// 同じセッションの解析の時系列です。届いていなければ `nil` です。
        let samples: [SessionLogAnalysisState.TimelineSample]?
        /// 重ね合わせです。
        let overlays: [RouteAnalysisOverlay]
        /// 利用者が選んでいる色分けの元です。
        let preferredSource: RouteAnalysisColorSource?
    }

    /// 作り直しの結果です。
    nonisolated private struct RebuildOutput: Sendable {
        /// 時刻を揃えた時間の軸です。
        let timeline: RouteAnalysisTimeline
        /// 色分けの選択肢です。
        let options: [RouteAnalysisColorSourceOption]
        /// 実際に使った色分けの元です。
        let source: RouteAnalysisColorSource?
        /// 色分け中の指標の値の列です(指標で色分けしていない時は `nil`)。
        let values: RouteAnalysisValueSeries?
        /// 色分け中の指標の値の単位です。
        let unit: String?
        /// 地図に描く内容です。
        let layers: RouteAnalysisMapLayers
        /// 指標のグラフです。
        let metricChart: RouteAnalysisChartSeries?
        /// 標高のグラフです。
        let elevationChart: RouteAnalysisChartSeries?
        /// 色分けから生じた注記のキーです。
        let noticeKeys: [String]
        /// グラフで強調する時刻の範囲です。
        let highlightedTimeRanges: [ClosedRange<Date>]
    }

    /// 作り直しに使う純粋な部品の組です。
    private typealias RebuildParts = (
        alignmentPolicy: TelemetryTimeAlignmentPolicy,
        timelineBuilder: RouteAnalysisTimelineBuilder,
        extractor: RouteAnalysisValueSeriesExtractor,
        catalog: RouteAnalysisColorSourceCatalog,
        layerBuilder: RouteAnalysisMapLayerBuilder,
        chartBuilder: RouteAnalysisChartSeriesBuilder
    )

    /// 指標で色分けしたのに、位置と時刻の合う値が1つも無い時の注記キーです。
    nonisolated private static let noMatchingValuesKey = "analysis.route.notice.no_matching_values"
    /// 時系列はあるが、色分けに使える元が無い時の注記キーです。
    nonisolated private static let noColorSourceKey = "analysis.route.notice.no_color_source"
    /// ポートが取消以外を投げた時(契約違反)に出す失敗のキーです。
    private static let unexpectedFailureKey = "history.route.failure.load"

    /// 画面へ公開する状態です。
    private(set) var state = RouteAnalysisState()

    /// 走行ルートを読み込むポートです。
    @ObservationIgnored private let trackPort: any RouteAnalysisTrackPort
    /// 作り直しに使う純粋な部品です。
    @ObservationIgnored private let parts: RebuildParts
    /// グラフで選んだ時刻の読み出しを求める部品です。
    @ObservationIgnored private let cursorResolver: RouteAnalysisCursorResolver
    /// サインイン中のアカウント識別子です。サインインしていなければ `nil` です。
    @ObservationIgnored private var accountIdentifier: String?
    /// 表示中のセッションです。表示していなければ `nil` です。
    @ObservationIgnored private var session: ConnectionSession?
    /// 受け取った解析の時系列と、そのセッション ID です。
    @ObservationIgnored private var receivedTimeline: (sessionID: ConnectionSessionID, samples: [SessionLogAnalysisState.TimelineSample])?
    /// 受け取った重ね合わせです。
    @ObservationIgnored private var overlays: [RouteAnalysisOverlay] = []
    /// 読み込んだ走行ルートと注記のキーです。
    @ObservationIgnored private var loaded: (route: DrivingRoute, noticeKeys: [String])?
    /// 最新の作り直しの結果です。
    @ObservationIgnored private var analysis: RebuildOutput?
    /// グラフで選んでいる時刻です。
    @ObservationIgnored private var selectedDate: Date?
    /// 実行中の読み込みです。
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    /// 実行中の作り直しです。
    @ObservationIgnored private var rebuildTask: Task<Void, Never>?
    /// 読み込みの世代の番号です。
    @ObservationIgnored private var loadGeneration = 0
    /// 作り直しの世代の番号です。
    @ObservationIgnored private var rebuildGeneration = 0

    /// ポートと純粋な部品を固定して生成します。
    ///
    /// 責務: 読み込みのポートと、時刻合わせ・時間の軸・値の列・選択肢・地図・グラフ・読み出しの部品を保持し、`idle` から始めます。
    /// - Parameters:
    ///   - trackPort: 走行ルートを読み込むポート。
    ///   - alignmentPolicy: 時計の選び方を決める部品。
    ///   - timelineBuilder: 時間の軸を作る部品。
    ///   - extractor: 指標の値の列を取り出す部品。
    ///   - catalog: 色分けの選択肢を作る部品。
    ///   - layerBuilder: 地図に描く内容を作る部品。
    ///   - chartBuilder: グラフの系列を作る部品。
    ///   - cursorResolver: グラフで選んだ時刻の読み出しを求める部品。
    init(
        trackPort: any RouteAnalysisTrackPort,
        alignmentPolicy: TelemetryTimeAlignmentPolicy = .init(),
        timelineBuilder: RouteAnalysisTimelineBuilder = .init(),
        extractor: RouteAnalysisValueSeriesExtractor = .init(),
        catalog: RouteAnalysisColorSourceCatalog = .init(),
        layerBuilder: RouteAnalysisMapLayerBuilder = .init(),
        chartBuilder: RouteAnalysisChartSeriesBuilder = .init(),
        cursorResolver: RouteAnalysisCursorResolver = .init()
    ) {
        self.trackPort = trackPort
        self.parts = (alignmentPolicy, timelineBuilder, extractor, catalog, layerBuilder, chartBuilder)
        self.cursorResolver = cursorResolver
    }

    /// 実行中の読み込みと作り直しを取り消します。
    deinit {
        loadTask?.cancel()
        rebuildTask?.cancel()
    }

    /// 画面からの操作を受け取ります。
    ///
    /// 責務: Action の種類ごとに、アカウント・表示・時系列・色分け・時刻・重ね合わせ・再試行・閉じる処理へ振り分けます。
    /// - Parameter action: 画面からの操作。
    func send(_ action: RouteAnalysisAction) {
        switch action {
        case .accountIdentifierChanged(let identifier):
            changeAccount(to: identifier)
        case .sessionShown(let session):
            show(session)
        case .timelineLoaded(let sessionID, let samples):
            receiveTimeline(samples, for: sessionID)
        case .colorSourceSelected(let source):
            selectColorSource(source)
        case .timeSelected(let date):
            updateCursor(at: date)
        case .mapCoordinateSelected(let coordinate):
            updateCursor(at: analysis.flatMap { cursorResolver.date(nearestTo: coordinate, in: $0.timeline) })
        case .overlaysChanged(let overlays):
            self.overlays = overlays
            scheduleRebuild()
        case .retryRequested:
            retry()
        case .dismissed:
            dismiss()
        }
    }

    /// 実行中の読み込みと作り直し(置き換わったものを含む)が終わるまで待ちます。テスト用です。
    ///
    /// 責務: 実行中の Task の終了を順に待ち、同じ Task が残っていれば待つのをやめます。
    func waitUntilIdle() async {
        while let task = loadTask ?? rebuildTask {
            await task.value
            if loadTask == task || rebuildTask == task {
                return
            }
        }
    }

    /// アカウントの変更を反映します。
    ///
    /// 責務: 値が変わった時だけ読み込みと内容を捨て、別のアカウントへ移る時は受け取った時系列も捨てます。表示中のセッションがあれば読み直します。
    /// - Parameter identifier: 新しいアカウント識別子(空文字はサインインなしとみなします)。
    private func changeAccount(to identifier: String?) {
        let normalized = identifier?.isEmpty == true ? nil : identifier
        guard normalized != accountIdentifier else {
            return
        }
        if accountIdentifier != nil {
            receivedTimeline = nil
        }
        accountIdentifier = normalized
        resetLoad()
        state = RouteAnalysisState(sessionID: session?.id)
        beginLoad()
    }

    /// セッションの表示を反映します。
    ///
    /// 責務: 同じセッションを読み込み中・待機中・表示中なら何もせず、それ以外は前の内容を捨てて読み始めます。
    /// - Parameter session: 表示されたセッション。
    private func show(_ session: ConnectionSession) {
        let isActive = state.phase == .loading || state.phase == .ready || state.phase == .waitingForAccount
        if self.session?.id == session.id, isActive {
            return
        }
        resetLoad()
        self.session = session
        state = RouteAnalysisState(sessionID: session.id)
        beginLoad()
    }

    /// 解析の時系列を受け取ります。
    ///
    /// 責務: セッション ID と一緒に保持し、同じセッションのルートを読み込み済みなら作り直します(別のセッションの時系列は表示へ使いません)。
    /// - Parameters:
    ///   - samples: 解析の時系列。
    ///   - sessionID: 時系列のセッション ID。
    private func receiveTimeline(_ samples: [SessionLogAnalysisState.TimelineSample], for sessionID: ConnectionSessionID) {
        receivedTimeline = (sessionID, samples)
        guard session?.id == sessionID, loaded != nil else {
            return
        }
        scheduleRebuild()
    }

    /// 色分けの元の選択を反映します。
    ///
    /// 責務: 選べる選択肢で、今の選択と異なる時だけ選択を変えて作り直します。
    /// - Parameter source: 選ばれた色分けの元。
    private func selectColorSource(_ source: RouteAnalysisColorSource) {
        let isSelectable = state.colorSourceOptions.contains { $0.source == source && $0.isEnabled }
        guard loaded != nil, isSelectable, state.selectedColorSource != source else {
            return
        }
        state.selectedColorSource = source
        scheduleRebuild()
    }

    /// グラフで選んだ時刻の読み出しを更新します。
    ///
    /// 責務: 時刻を覚え、作り直しの結果がある時だけ読み出しを求めます(`nil` なら消します)。
    /// - Parameter date: 選んだ時刻。離した時は `nil`。
    private func updateCursor(at date: Date?) {
        selectedDate = date
        guard let date, let analysis else {
            state.cursor = nil
            return
        }
        state.cursor = cursorResolver.cursor(at: date, timeline: analysis.timeline, values: analysis.values, unit: analysis.unit)
    }

    /// 再試行の要求を反映します。
    ///
    /// 責務: 再試行できる失敗の時だけ読み直します。
    private func retry() {
        guard case .failed(_, let isRetryable) = state.phase, isRetryable, session != nil else {
            return
        }
        resetLoad()
        state = RouteAnalysisState(sessionID: session?.id)
        beginLoad()
    }

    /// ルートの表示を閉じます。
    ///
    /// 責務: 読み込みと作り直しを取り消し、セッション・時系列・重ね合わせ・選択を捨てて初期の状態に戻します。
    private func dismiss() {
        resetLoad()
        session = nil
        receivedTimeline = nil
        overlays = []
        selectedDate = nil
        state = RouteAnalysisState()
    }

    /// 実行中の読み込みと作り直しを取り消し、読み込んだ内容を捨てます。
    ///
    /// 責務: Task を取り消して手放し、両方の世代を進めて、遅れて届く結果を古い世代として捨てさせます。
    private func resetLoad() {
        loadTask?.cancel()
        rebuildTask?.cancel()
        loadTask = nil
        rebuildTask = nil
        loadGeneration += 1
        rebuildGeneration += 1
        loaded = nil
        analysis = nil
    }

    /// 表示中のセッションの読み込みを始めます。
    ///
    /// 責務: セッションが無ければ何もせず、アカウントが無ければ待ちの状態にし、あれば `loading` にして新しい世代の読み込みを起動します。
    private func beginLoad() {
        guard let session else {
            return
        }
        guard let accountIdentifier else {
            state.phase = .waitingForAccount
            return
        }
        state.phase = .loading
        loadGeneration += 1
        let generation = loadGeneration
        loadTask = Task { [weak self] in
            await self?.performLoad(sessionID: session.id, accountIdentifier: accountIdentifier, generation: generation)
        }
    }

    /// 1回の読み込みを行い、結果を反映します。
    ///
    /// 責務: ポートから読み、世代が変わっていなければ結果を反映します。取消は状態を変えません。
    /// - Parameters:
    ///   - sessionID: 対象のセッション ID。
    ///   - accountIdentifier: 対象のアカウント。
    ///   - generation: この読み込みの世代。
    private func performLoad(sessionID: ConnectionSessionID, accountIdentifier: String, generation: Int) async {
        defer {
            if loadGeneration == generation {
                loadTask = nil
            }
        }
        let result: RouteAnalysisTrackLoadResult
        do {
            result = try await trackPort.loadRoute(sessionID: sessionID, accountIdentifier: accountIdentifier)
        } catch is CancellationError {
            return
        } catch {
            result = .failed(messageKey: Self.unexpectedFailureKey, isRetryable: true)
        }
        guard loadGeneration == generation else {
            return
        }
        applyLoadResult(result)
    }

    /// 読み込みの結果を状態へ反映します。
    ///
    /// 責務: 描ける時はルートと注記を覚えて作り直しを始め、描けない時と失敗はそのまま段階にします。
    /// - Parameter result: 読み込みの結果。
    private func applyLoadResult(_ result: RouteAnalysisTrackLoadResult) {
        switch result {
        case .available(let route, let noticeKeys):
            loaded = (route, noticeKeys)
            state.noticeKeys = noticeKeys
            scheduleRebuild()
        case .unavailable(let reasonKey, let systemImage):
            state.phase = .unavailable(reasonKey: reasonKey, systemImage: systemImage)
        case .failed(let messageKey, let isRetryable):
            state.phase = .failed(messageKey: messageKey, isRetryable: isRetryable)
        }
    }

    /// 今の入力で作り直しを始めます。
    ///
    /// 責務: ルートを読み込み済みの時だけ、前の作り直しを取り消し、ルート・同じセッションの時系列・重ね合わせ・選択を入力にして
    /// 新しい世代の作り直しを起動します(読み込み前に届いた重ね合わせは、読み込み後の作り直しで使います)。
    private func scheduleRebuild() {
        guard let loaded, let session else {
            return
        }
        rebuildTask?.cancel()
        rebuildGeneration += 1
        let generation = rebuildGeneration
        let samples = receivedTimeline?.sessionID == session.id ? receivedTimeline?.samples : nil
        let input = RebuildInput(route: loaded.route, samples: samples, overlays: overlays, preferredSource: state.selectedColorSource)
        rebuildTask = Task { [weak self] in
            await self?.performRebuild(input, generation: generation)
        }
    }

    /// 作り直しをメインの外で行い、世代が変わっていなければ結果を状態へ反映します。
    ///
    /// 責務: 純粋な作り直しを `Task.detached` へ渡して取消を伝え、結果の選択肢・色分け・グラフ・注記・強調を反映し、読み出しを更新します。
    /// - Parameters:
    ///   - input: 作り直しの入力。
    ///   - generation: この作り直しの世代。
    private func performRebuild(_ input: RebuildInput, generation: Int) async {
        defer {
            if rebuildGeneration == generation {
                rebuildTask = nil
            }
        }
        let parts = parts
        let task = Task.detached(priority: .userInitiated) { () -> RebuildOutput? in
            Task.isCancelled ? nil : Self.rebuilt(input, parts: parts)
        }
        let output = await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        guard let output, rebuildGeneration == generation, let loaded else {
            return
        }
        analysis = output
        state.colorSourceOptions = output.options
        state.selectedColorSource = output.source
        state.layers = output.layers
        state.metricChart = output.metricChart
        state.elevationChart = output.elevationChart
        state.highlightedTimeRanges = output.highlightedTimeRanges
        state.noticeKeys = loaded.noticeKeys + output.noticeKeys
        state.phase = .ready
        updateCursor(at: selectedDate)
    }

    /// 入力から、時間の軸・値の列・選択肢・色分けの元を決め、地図とグラフを作ります。
    ///
    /// 責務: 時系列がある時だけ時刻合わせと指標ごとの値の列を作り、選んでいる元が選べなければ既定の元にします。
    /// - Parameters:
    ///   - input: 作り直しの入力。
    ///   - parts: 純粋な部品。
    /// - Returns: 作り直しの結果。
    nonisolated private static func rebuilt(_ input: RebuildInput, parts: RebuildParts) -> RebuildOutput {
        var alignment = TelemetryTimeAlignment.wallClock
        var valueSeries: [RouteAnalysisColorMetric: RouteAnalysisValueSeries] = [:]
        if let samples = input.samples {
            let locations = parts.timelineBuilder.clockStamps(of: input.route)
            alignment = parts.alignmentPolicy.alignment(locations: locations, values: parts.extractor.clockStamps(in: samples))
            for metric in RouteAnalysisColorMetric.allCases {
                valueSeries[metric] = parts.extractor.series(for: metric.pid, in: samples, alignment: alignment)
            }
        }
        let timeline = parts.timelineBuilder.timeline(route: input.route, alignment: alignment)
        let options = parts.catalog.options(valueSeries: valueSeries, overlays: input.overlays)
        let isPreferredSelectable = options.contains { $0.source == input.preferredSource && $0.isEnabled }
        let source = isPreferredSelectable ? input.preferredSource : parts.catalog.defaultSource(in: options)
        return colored(timeline: timeline, valueSeries: valueSeries, options: options, source: source, input: input, parts: parts)
    }

    /// 決めた色分けの元で、地図・グラフ・注記・強調を作ります。
    ///
    /// 責務: 指標なら値の列で色分けして指標のグラフを作り、重ね合わせならその分類と強調の範囲を使い、元が無ければ色なしにします。
    /// - Parameters:
    ///   - timeline: 時間の軸。
    ///   - valueSeries: 指標ごとの値の列。
    ///   - options: 色分けの選択肢。
    ///   - source: 使う色分けの元。
    ///   - input: 作り直しの入力。
    ///   - parts: 純粋な部品。
    /// - Returns: 作り直しの結果。
    nonisolated private static func colored(
        timeline: RouteAnalysisTimeline,
        valueSeries: [RouteAnalysisColorMetric: RouteAnalysisValueSeries],
        options: [RouteAnalysisColorSourceOption],
        source: RouteAnalysisColorSource?,
        input: RebuildInput,
        parts: RebuildParts
    ) -> RebuildOutput {
        var coloring = RouteAnalysisColoring.none
        var metricValues: (metric: RouteAnalysisColorMetric, series: RouteAnalysisValueSeries)?
        var highlightedTimeRanges: [ClosedRange<Date>] = []
        if case .metric(let metric)? = source, let series = valueSeries[metric] {
            coloring = .metric(metric, series)
            metricValues = (metric, series)
        } else if case .overlay(let id)? = source, let overlay = input.overlays.first(where: { $0.id == id }) {
            coloring = .overlay(overlay)
            highlightedTimeRanges = overlay.highlightedTimeRanges
        }
        let layers = parts.layerBuilder.layers(timeline: timeline, coloring: coloring)
        let noticeKeys = coloringNoticeKeys(
            isMetricColoring: metricValues != nil,
            layers: layers,
            hasSamples: input.samples != nil,
            source: source
        )
        return RebuildOutput(
            timeline: timeline,
            options: options,
            source: source,
            values: metricValues?.series,
            unit: metricValues.map { $0.series.unit ?? $0.metric.fallbackUnit },
            layers: layers,
            metricChart: metricValues.flatMap { parts.chartBuilder.metricSeries($0.series, metric: $0.metric) },
            elevationChart: parts.chartBuilder.elevationSeries(timeline),
            noticeKeys: noticeKeys,
            highlightedTimeRanges: highlightedTimeRanges
        )
    }

    /// 色分けから生じる注記のキーを返します。
    ///
    /// 責務: 指標で色分けしたのに値が1つも合わない時と、時系列はあるのに色分けの元が無い時の注記を、この順に並べます。
    /// - Parameters:
    ///   - isMetricColoring: 指標で色分けした時に `true`。
    ///   - layers: 作った地図の内容。
    ///   - hasSamples: 解析の時系列を受け取っている時に `true`。
    ///   - source: 使った色分けの元。
    /// - Returns: 注記のキー。
    nonisolated private static func coloringNoticeKeys(
        isMetricColoring: Bool,
        layers: RouteAnalysisMapLayers,
        hasSamples: Bool,
        source: RouteAnalysisColorSource?
    ) -> [String] {
        var noticeKeys: [String] = []
        if isMetricColoring, !layers.hasMatchedValues {
            noticeKeys.append(noMatchingValuesKey)
        }
        if hasSamples, source == nil {
            noticeKeys.append(noColorSourceKey)
        }
        return noticeKeys
    }
}
