#if os(macOS)
import Charts
import SwiftUI

/// macOSのセッション解析で切り替える表示単位です。
private enum MacOSSessionLogAnalysisMode: String, CaseIterable, Identifiable {
    /// 走行時間、距離、速度帯、回転域、部品・系統を確認します。
    case overview
    /// 1件のPIDを時間軸で確認します。
    case trends
    /// 2件のPIDの関係を散布図で確認します。
    case relationships

    /// Pickerで使用する安定識別子です。
    var id: String { rawValue }
    /// 表示モード名のローカライズキーです。
    var titleKey: LocalizedStringKey {
        switch self {
        case .overview: "analysis.mode.overview"
        case .trends: "analysis.mode.trends"
        case .relationships: "analysis.mode.relationships"
        }
    }
}

/// macOS向けに保存済みPIDログを走行サマリー、グラフ、Raw根拠へ整理します。
struct MacOSSessionLogAnalysisView: View {
    /// 表示するセッションです。
    let session: ConnectionSession
    /// Analysisが提供する時系列解析状態です。
    let state: SessionLogAnalysisState
    /// Analysisの型付き操作をApplicationへ通知します。
    let send: (SessionLogAnalysisAction) -> Void
    /// 現在のウインドウ寸法に対応する表示寸法です。
    let metrics: MacOSAppShellMetrics
    /// 現在選択中の解析表示です。
    @State private var mode: MacOSSessionLogAnalysisMode = .overview
    /// 折れ線グラフへ表示するPIDです。
    @State private var selectedSeriesID: OBDPIDRequest?
    /// 散布図へ表示するPID組です。
    @State private var selectedRelationshipID: String?
    /// NavigationStackの直前画面へ戻す環境操作です。
    @Environment(\.dismiss) private var dismiss

    /// 接続履歴と同じ視覚階層でセッション解析を提供します。
    ///
    /// 責務: 1件のセッション解析状態をmacOS向け走行サマリーとグラフへ変換します。
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20 * metrics.scale) {
                navigationBar
                hero
                summary
                modePicker
                selectedContent
            }
            .padding(28 * metrics.scale)
            .frame(maxWidth: 1_180 * metrics.scale)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(background)
        .navigationTitle("analysis.title")
        .navigationBarBackButtonHidden(true)
        .onAppear {
            if state.sessionID != session.id { send(.sessionSelected(session)) }
            selectDefaults()
        }
        .onChange(of: state.pidSeries.map(\.id)) { _, _ in selectDefaults() }
        .onChange(of: state.relationships.map(\.id)) { _, _ in selectDefaults() }
        .accessibilityIdentifier("macos-session-log-analysis")
    }

    /// セッション詳細へ戻る操作を表示します。
    private var navigationBar: some View {
        HStack {
            Button {
                send(.dismissed)
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14 * metrics.scale, weight: .bold))
                    .frame(width: 44 * metrics.scale, height: 44 * metrics.scale)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .background(Color.primary.opacity(0.065), in: RoundedRectangle(cornerRadius: 14 * metrics.scale, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14 * metrics.scale, style: .continuous)
                    .stroke(Color.primary.opacity(0.08))
            }
            .accessibilityLabel(Text("analysis.back.session"))
            .accessibilityIdentifier("macos-analysis-session-back")
            .help(Text("analysis.back.session"))
            Spacer()
        }
    }

    /// 解析対象とRawログ件数を接続履歴と同じ主カードで示します。
    private var hero: some View {
        HStack(spacing: 20 * metrics.scale) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 31 * metrics.scale, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 76 * metrics.scale, height: 76 * metrics.scale)
                .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 22 * metrics.scale, style: .continuous))
            VStack(alignment: .leading, spacing: 5 * metrics.scale) {
                Text("analysis.eyebrow")
                    .font(.system(size: 10 * metrics.scale, weight: .bold, design: .rounded))
                    .tracking(1.8 * metrics.scale)
                    .foregroundStyle(.tint)
                Text(session.vehicle?.name ?? String(localized: "history.vehicle.pending"))
                    .font(.system(size: 30 * metrics.scale, weight: .bold, design: .rounded))
                Text(session.startedAt, format: .dateTime.year().month().day().hour().minute().second())
                    .font(.system(size: 12 * metrics.scale, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4 * metrics.scale) {
                Text(session.rawLogSummary.recordCount, format: .number)
                    .font(.system(size: 24 * metrics.scale, weight: .bold, design: .rounded))
                Text("analysis.summary.samples")
                    .font(.system(size: 10 * metrics.scale, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24 * metrics.scale)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28 * metrics.scale, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 28 * metrics.scale, style: .continuous).stroke(Color.primary.opacity(0.08)) }
    }

    /// 読込済み、数値化済み、Raw保持の件数を表示します。
    private var summary: some View {
        HStack(spacing: 12 * metrics.scale) {
            metric(state.timeline.count, key: "analysis.summary.samples", symbol: "waveform.path.ecg", color: .cyan)
            metric(state.decodedSampleCount, key: "analysis.summary.decoded", symbol: "function", color: .green)
            metric(state.rawOnlySampleCount, key: "analysis.summary.raw", symbol: "shippingbox", color: .orange)
        }
    }

    /// 解析の3種類を明示的に切り替えます。
    private var modePicker: some View {
        Picker("analysis.mode.title", selection: $mode) {
            ForEach(MacOSSessionLogAnalysisMode.allCases) { item in
                Text(item.titleKey).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("macos-analysis-mode")
    }

    /// 現在の読込段階または選択モードを描画します。
    @ViewBuilder private var selectedContent: some View {
        if state.phase == .loading && state.timeline.isEmpty {
            ProgressView("analysis.loading").frame(maxWidth: .infinity).padding(40 * metrics.scale)
        } else if state.phase == .failed && state.timeline.isEmpty {
            HStack(spacing: 10 * metrics.scale) {
                WarningTriangleIcon(size: 18 * metrics.scale, color: .red)
                Text("analysis.error.storage")
            }
            .foregroundStyle(.red)
        } else if state.phase == .loaded && state.timeline.isEmpty {
            ContentUnavailableView("analysis.empty.title", systemImage: "waveform.slash", description: Text("analysis.empty.body"))
        } else {
            if state.phase == .loading { analysisProgress }
            switch mode {
            case .overview: sessionOverview
            case .trends: trends
            case .relationships: relationships
            }
        }
    }

    /// セッション時間、距離、速度帯、回転域、部品・系統を一覧化します。
    private var sessionOverview: some View {
        VStack(alignment: .leading, spacing: 16 * metrics.scale) {
            analysisCard(title: "analysis.overview.title", subtitle: "analysis.overview.subtitle") {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 190 * metrics.scale), spacing: 12 * metrics.scale)],
                    spacing: 12 * metrics.scale
                ) {
                    overviewMetric(value: sessionDurationText, key: "analysis.overview.session_duration", symbol: "clock")
                    overviewMetric(value: movingDurationText, key: "analysis.overview.moving_duration", symbol: "car.side")
                    overviewMetric(value: distanceText, key: distanceTitleKey, symbol: "road.lanes")
                }
                Text("analysis.overview.estimate_note").font(.caption).foregroundStyle(.secondary)
            }
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 320 * metrics.scale), spacing: 14 * metrics.scale)],
                alignment: .leading,
                spacing: 14 * metrics.scale
            ) {
                durationRanking(
                    title: "analysis.overview.speed_ranking",
                    subtitle: "analysis.overview.speed_ranking_note",
                    bands: state.performanceSummary.speedBands,
                    unitKey: "analysis.overview.speed_band"
                )
                durationRanking(
                    title: "analysis.overview.rpm_ranking",
                    subtitle: "analysis.overview.rpm_ranking_note",
                    bands: state.performanceSummary.rpmBands,
                    unitKey: "analysis.overview.rpm_band"
                )
            }
            componentOverview
        }
    }

    /// 選択PIDの時間変化を1単位ずつ折れ線グラフで表示します。
    @ViewBuilder private var trends: some View {
        if let series = selectedSeries {
            analysisCard(title: "analysis.trend.title", subtitle: "analysis.trend.subtitle") {
                Picker("analysis.trend.pid", selection: $selectedSeriesID) {
                    ForEach(state.pidSeries) { item in
                        Text(seriesName(item)).tag(Optional(item.id))
                    }
                }
                trendGuide(series)
                Chart(series.points) { point in
                    LineMark(
                        x: .value(String(localized: "analysis.chart.time"), point.observedAt),
                        y: .value(String(localized: "analysis.chart.value"), point.value)
                    )
                    .foregroundStyle(Color.accentColor)
                    .interpolationMethod(.linear)
                }
                .chartYAxisLabel(series.unit)
                .frame(minHeight: 300 * metrics.scale)
            }
        } else {
            ContentUnavailableView("analysis.trend.empty.title", systemImage: "chart.xyaxis.line", description: Text("analysis.trend.empty.body"))
        }
    }

    /// 選択PIDの識別子、意味、統計値、解釈上の注意を表示します。
    ///
    /// 責務: 1件のPID系列を折れ線グラフの読解ガイドへ変換します。
    /// - Parameter series: 説明するPID系列。
    /// - Returns: PIDの来歴と観測可能範囲を示す案内表示。
    private func trendGuide(_ series: SessionPIDSeries) -> some View {
        VStack(alignment: .leading, spacing: 8 * metrics.scale) {
            HStack(spacing: 8 * metrics.scale) {
                Text(pidLabel(service: series.id.service, pid: series.id.pid))
                    .font(.system(size: 11 * metrics.scale, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.tint)
                if let modelCode = series.vehicleModelCode {
                    VehicleModelBadge(modelCode: modelCode)
                }
            }
            Text(String(localized: String.LocalizationValue(series.interpretationKey)))
                .font(.system(size: 11 * metrics.scale))
                .foregroundStyle(.secondary)
            HStack(spacing: 24 * metrics.scale) {
                statistic("analysis.trend.minimum", value: series.minimumValue, unit: series.unit)
                statistic("analysis.trend.average", value: series.averageValue, unit: series.unit)
                statistic("analysis.trend.maximum", value: series.maximumValue, unit: series.unit)
            }
        }
        .padding(13 * metrics.scale)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 14 * metrics.scale, style: .continuous))
    }

    /// 取得できたPIDを部品・系統別の観察カードとして表示します。
    private var componentOverview: some View {
        analysisCard(title: "analysis.components.title", subtitle: "analysis.components.subtitle") {
            if state.componentInsights.isEmpty {
                Text("analysis.components.empty").font(.caption).foregroundStyle(.secondary)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 300 * metrics.scale), spacing: 12 * metrics.scale)],
                    spacing: 12 * metrics.scale
                ) {
                    ForEach(state.componentInsights) { insight in
                        VStack(alignment: .leading, spacing: 6 * metrics.scale) {
                            Label(componentTitleKey(insight.component), systemImage: componentSymbol(insight.component))
                                .font(.system(size: 13 * metrics.scale, weight: .semibold))
                            HStack(spacing: 8 * metrics.scale) {
                                Text(seriesName(insight.series)).font(.system(size: 12 * metrics.scale, weight: .semibold))
                                if let modelCode = insight.series.vehicleModelCode {
                                    VehicleModelBadge(modelCode: modelCode)
                                }
                            }
                            Text(componentDescriptionKey(insight.component)).font(.system(size: 10 * metrics.scale)).foregroundStyle(.secondary)
                            Text(statisticsText(insight.series)).font(.system(size: 10 * metrics.scale, design: .monospaced)).foregroundStyle(.secondary)
                        }
                        .padding(14 * metrics.scale)
                        .frame(maxWidth: .infinity, minHeight: 132 * metrics.scale, alignment: .topLeading)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16 * metrics.scale, style: .continuous))
                    }
                }
            }
        }
    }

    /// 数値帯ランキングを推定滞在時間と構成比で表示します。
    ///
    /// 責務: 1件の時間帯ランキングをmacOS向け順位カードへ変換します。
    /// - Parameters:
    ///   - title: ランキング見出し。
    ///   - subtitle: 集計方法の説明。
    ///   - bands: 滞在時間順の数値帯。
    ///   - unitKey: 数値帯書式のローカライズキー。
    /// - Returns: 最大5件の順位またはデータ不足表示。
    private func durationRanking(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        bands: [SessionDurationBand],
        unitKey: String
    ) -> some View {
        analysisCard(title: title, subtitle: subtitle) {
            if bands.isEmpty {
                Text("analysis.overview.ranking_empty").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(Array(bands.enumerated()), id: \.element.id) { index, band in
                    HStack {
                        Text("\(index + 1)")
                            .font(.system(size: 15 * metrics.scale, weight: .bold, design: .monospaced))
                            .foregroundStyle(.tint)
                            .frame(width: 28 * metrics.scale)
                        VStack(alignment: .leading, spacing: 2 * metrics.scale) {
                            Text(bandText(band, key: unitKey)).font(.system(size: 12 * metrics.scale, weight: .semibold))
                            Text(band.proportion, format: .percent.precision(.fractionLength(0))).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(durationText(band.duration)).font(.system(size: 12 * metrics.scale, design: .monospaced))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    /// 代表PID組を近接時刻で対応付けた散布図で表示します。
    @ViewBuilder private var relationships: some View {
        if let relationship = selectedRelationship {
            analysisCard(title: "analysis.relationship.title", subtitle: "analysis.relationship.subtitle") {
                Picker("analysis.relationship.pair", selection: $selectedRelationshipID) {
                    ForEach(state.relationships) { item in
                        Text(relationshipName(item)).tag(Optional(item.id))
                    }
                }
                relationshipGuide(relationship)
                if let modelCode = relationship.xSeries.vehicleModelCode ?? relationship.ySeries.vehicleModelCode {
                    VehicleModelBadge(modelCode: modelCode)
                }
                Chart(relationship.points) { point in
                    PointMark(
                        x: .value(seriesName(relationship.xSeries), point.x),
                        y: .value(seriesName(relationship.ySeries), point.y)
                    )
                    .foregroundStyle(Color.indigo.opacity(0.72))
                }
                .chartXAxisLabel(relationship.xSeries.unit)
                .chartYAxisLabel(relationship.ySeries.unit)
                .frame(minHeight: 300 * metrics.scale)
            }
        } else {
            ContentUnavailableView("analysis.relationship.empty.title", systemImage: "chart.dots.scatter", description: Text("analysis.relationship.empty.body"))
        }
    }

    /// 選択中の散布図について共通の読み方とPID組固有の観察目的を表示します。
    ///
    /// 責務: 1件のPID相関候補を誤診断を避ける利用解説へ変換します。
    /// - Parameter relationship: 解説対象のPID相関候補。
    /// - Returns: 散布点の読み方と選択組の観察目的を持つ案内表示。
    private func relationshipGuide(_ relationship: SessionPIDRelationship) -> some View {
        VStack(alignment: .leading, spacing: 7 * metrics.scale) {
            Label("analysis.relationship.guide.title", systemImage: "info.circle.fill")
                .font(.system(size: 12 * metrics.scale, weight: .semibold))
                .foregroundStyle(.indigo)
            Text("analysis.relationship.guide.common")
            Text(relationshipGuideKey(relationship))
        }
        .font(.system(size: 11 * metrics.scale))
        .foregroundStyle(.secondary)
        .padding(13 * metrics.scale)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.indigo.opacity(0.07), in: RoundedRectangle(cornerRadius: 14 * metrics.scale, style: .continuous))
    }

    /// PID組を散布図で観察できる内容のローカライズキーへ変換します。
    ///
    /// 責務: 1件の既定PID相関候補へ対応する観察目的を選択します。
    /// - Parameter relationship: 解説対象のPID相関候補。
    /// - Returns: PID組固有の観察目的を示すローカライズキー。
    private func relationshipGuideKey(_ relationship: SessionPIDRelationship) -> LocalizedStringKey {
        switch (
            relationship.xSeries.id.service,
            relationship.xSeries.id.pid,
            relationship.ySeries.id.service,
            relationship.ySeries.id.pid
        ) {
        case (0x01, 0x0C, 0x01, 0x0D): "analysis.relationship.guide.rpm_speed"
        case (0x01, 0x0C, 0x01, 0x04): "analysis.relationship.guide.rpm_load"
        case (0x01, 0x0C, 0x01, 0x10): "analysis.relationship.guide.rpm_maf"
        case (0x01, 0x11, 0x01, 0x04): "analysis.relationship.guide.throttle_load"
        case (0x01, 0x06, 0x01, 0x07): "analysis.relationship.guide.trim_banks"
        case (0x01, 0x0D, 0x21, 0x17): "analysis.relationship.guide.speed_zd8_atf"
        default: "analysis.relationship.guide.common"
        }
    }

    /// 共通見出しを持つ解析カードを生成します。
    ///
    /// 責務: 1件の解析内容を見出しと説明を持つmacOSカードへ変換します。
    /// - Parameters:
    ///   - title: カード見出しのローカライズキー。
    ///   - subtitle: カード説明のローカライズキー。
    ///   - content: カード内へ描画する解析内容。
    /// - Returns: 接続履歴と同じ素材階層の解析カード。
    private func analysisCard<Content: View>(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14 * metrics.scale) {
            Text(title).font(.system(size: 20 * metrics.scale, weight: .bold, design: .rounded))
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
            content()
        }
        .padding(20 * metrics.scale)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22 * metrics.scale, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 22 * metrics.scale, style: .continuous).stroke(Color.primary.opacity(0.07)) }
    }

    /// 1件の解析集計をカードへ変換します。
    ///
    /// 責務: 1件の解析件数をアイコンと見出しを持つmacOSカードへ変換します。
    /// - Parameters:
    ///   - value: 表示する件数。
    ///   - key: 集計見出しのローカライズキー。
    ///   - symbol: 集計概念を示すSF Symbol。
    ///   - color: 集計カードのアクセント色。
    /// - Returns: 同じ幅で並べられる集計カード。
    private func metric(_ value: Int, key: LocalizedStringKey, symbol: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8 * metrics.scale) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(value.formatted()).font(.system(size: 24 * metrics.scale, weight: .bold, design: .rounded))
            Text(key).font(.system(size: 11 * metrics.scale)).foregroundStyle(.secondary)
        }
        .padding(17 * metrics.scale)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20 * metrics.scale, style: .continuous))
    }

    /// 走行サマリーの1件を値、見出し、シンボルで表示します。
    ///
    /// 責務: 1件の表示済み走行集計をmacOS向け小型カードへ変換します。
    /// - Parameters:
    ///   - value: 表示用に整形済みの値。
    ///   - key: 値の意味を示すローカライズキー。
    ///   - symbol: 集計概念を示すSF Symbol。
    /// - Returns: 走行サマリー内の小型カード。
    private func overviewMetric(value: String, key: LocalizedStringKey, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 7 * metrics.scale) {
            Image(systemName: symbol).foregroundStyle(.tint)
            Text(value).font(.system(size: 19 * metrics.scale, weight: .bold, design: .rounded)).monospacedDigit()
            Text(key).font(.system(size: 10 * metrics.scale)).foregroundStyle(.secondary)
        }
        .padding(15 * metrics.scale)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16 * metrics.scale, style: .continuous))
    }

    /// 統計名と値を縦に並べて表示します。
    ///
    /// 責務: 1件のPID統計値を折れ線ガイド内の短い表示へ変換します。
    /// - Parameters:
    ///   - key: 最小・平均・最大の見出し。
    ///   - value: 表示する数値。
    ///   - unit: PID定義の単位。
    /// - Returns: 見出し付き統計値。
    private func statistic(_ key: LocalizedStringKey, value: Double, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2 * metrics.scale) {
            Text(key).font(.caption2).foregroundStyle(.secondary)
            Text(measurementText(value, unit: unit)).font(.system(size: 11 * metrics.scale, weight: .semibold, design: .monospaced))
        }
    }

    /// 逐次変換済み件数を全Rawログ件数に対する進捗として表示します。
    private var analysisProgress: some View {
        ProgressView(value: Double(state.timeline.count), total: Double(max(state.totalSampleCount ?? state.timeline.count, 1))) {
            Text("analysis.loading")
        } currentValueLabel: {
            Text("\(state.timeline.count.formatted()) / \((state.totalSampleCount ?? state.timeline.count).formatted())")
        }
        .font(.caption)
    }

    /// 現在選択中または先頭の折れ線系列です。
    private var selectedSeries: SessionPIDSeries? {
        state.pidSeries.first(where: { $0.id == selectedSeriesID }) ?? state.pidSeries.first
    }

    /// 現在選択中または先頭の散布図系列です。
    private var selectedRelationship: SessionPIDRelationship? {
        state.relationships.first(where: { $0.id == selectedRelationshipID }) ?? state.relationships.first
    }

    /// 読込済み系列から未選択の折れ線と散布図へ初期値を設定します。
    ///
    /// 責務: 現在の解析系列を未選択Pickerの先頭選択へ反映します。
    private func selectDefaults() {
        if selectedSeriesID == nil { selectedSeriesID = state.pidSeries.first?.id }
        if selectedRelationshipID == nil { selectedRelationshipID = state.relationships.first?.id }
    }

    /// PID系列の定義名または識別子を返します。
    ///
    /// 責務: 1件のPID系列をローカライズ済み表示名へ変換します。
    /// - Parameter series: 表示名を求めるPID系列。
    /// - Returns: 定義名またはService/PID識別子。
    private func seriesName(_ series: SessionPIDSeries) -> String {
        series.nameKey.map { String(localized: String.LocalizationValue($0)) }
            ?? pidLabel(service: series.id.service, pid: series.id.pid)
    }

    /// 散布図の2軸名を短い組名へ変換します。
    ///
    /// 責務: 1件のPID相関候補を横軸名と縦軸名の表示文字列へ変換します。
    /// - Parameter relationship: 表示するPID相関候補。
    /// - Returns: 2件のPID名を矢印で結んだ文字列。
    private func relationshipName(_ relationship: SessionPIDRelationship) -> String {
        "\(seriesName(relationship.xSeries)) × \(seriesName(relationship.ySeries))"
    }

    /// セッション開始から終了までの接続時間を表示文字列へ変換します。
    private var sessionDurationText: String {
        guard let endedAt = session.endedAt else { return String(localized: "analysis.value.in_progress") }
        return durationText(max(endedAt.timeIntervalSince(session.startedAt), 0))
    }

    /// 車速観測から推定した走行時間を表示文字列へ変換します。
    private var movingDurationText: String {
        state.performanceSummary.estimatedMovingDuration.map(durationText) ?? String(localized: "analysis.value.unavailable")
    }

    /// 保存済み距離差または車速積算の参考距離を表示します。
    private var distanceText: String {
        if let distance = session.recordedDistanceKilometers { return measurementText(distance, unit: "km") }
        guard let distance = state.performanceSummary.estimatedDistanceKilometers else {
            return String(localized: "analysis.value.unavailable")
        }
        return String(format: String(localized: "analysis.value.estimated_distance"), locale: .autoupdatingCurrent, distance)
    }

    /// 距離値の取得元に対応する見出しです。
    private var distanceTitleKey: LocalizedStringKey {
        session.recordedDistanceKilometers == nil ? "analysis.overview.estimated_distance" : "analysis.overview.distance"
    }

    /// 数値帯を下限と上限を持つ表示文字列へ変換します。
    ///
    /// 責務: 1件の数値帯をローカライズ済み範囲表記へ変換します。
    /// - Parameters:
    ///   - band: 表示する数値帯。
    ///   - key: 単位ごとの書式キー。
    /// - Returns: 下限以上かつ上限未満を表す文字列。
    private func bandText(_ band: SessionDurationBand, key: String) -> String {
        String(
            format: String(localized: String.LocalizationValue(key)),
            locale: .autoupdatingCurrent,
            band.lowerBound,
            band.upperBound
        )
    }

    /// 秒数を時分秒の短い表示へ変換します。
    ///
    /// 責務: 1件の秒数を現在ロケールの簡潔な時間表示へ変換します。
    /// - Parameter duration: 表示する秒数。
    /// - Returns: 秒までを含む省略単位形式。
    private func durationText(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = duration >= 3_600 ? [.hour, .minute] : duration >= 60 ? [.minute, .second] : [.second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter.string(from: duration) ?? String(localized: "analysis.value.unavailable")
    }

    /// 数値と単位を現在ロケールの短い表示へ変換します。
    ///
    /// 責務: 1件の有限数値とPID単位を小数1桁の表示へ変換します。
    /// - Parameters:
    ///   - value: 表示する数値。
    ///   - unit: PID定義の単位。
    /// - Returns: 数値と単位を結合した文字列。
    private func measurementText(_ value: Double, unit: String) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0...1)))) \(unit)"
    }

    /// 部品・系統分類を表示見出しへ変換します。
    ///
    /// 責務: 1件の部品・系統分類をローカライズキーへ変換します。
    /// - Parameter component: 表示する部品・系統分類。
    /// - Returns: 対応する見出しキー。
    private func componentTitleKey(_ component: SessionComponentInsight.Component) -> LocalizedStringKey {
        switch component {
        case .electrical: "analysis.components.electrical.title"
        case .thermal: "analysis.components.thermal.title"
        case .fuelAndIntake: "analysis.components.fuel_intake.title"
        case .exhaust: "analysis.components.exhaust.title"
        case .diagnostics: "analysis.components.diagnostics.title"
        }
    }

    /// 部品・系統分類を説明文へ変換します。
    ///
    /// 責務: 1件の部品・系統分類を安全な観察目的のローカライズキーへ変換します。
    /// - Parameter component: 説明する部品・系統分類。
    /// - Returns: 対応する説明キー。
    private func componentDescriptionKey(_ component: SessionComponentInsight.Component) -> LocalizedStringKey {
        switch component {
        case .electrical: "analysis.components.electrical.body"
        case .thermal: "analysis.components.thermal.body"
        case .fuelAndIntake: "analysis.components.fuel_intake.body"
        case .exhaust: "analysis.components.exhaust.body"
        case .diagnostics: "analysis.components.diagnostics.body"
        }
    }

    /// 部品・系統分類をSF Symbolへ変換します。
    ///
    /// 責務: 1件の部品・系統分類を識別用シンボルへ変換します。
    /// - Parameter component: 表示する部品・系統分類。
    /// - Returns: 対応するSF Symbol名。
    private func componentSymbol(_ component: SessionComponentInsight.Component) -> String {
        switch component {
        case .electrical: "bolt.12"
        case .thermal: "thermometer.medium"
        case .fuelAndIntake: "wind"
        case .exhaust: "aqi.medium"
        case .diagnostics: "wrench.and.screwdriver"
        }
    }

    /// PID系列の最小・平均・最大を1行へ整形します。
    ///
    /// 責務: 1件のPID系列統計を部品カード用の短い表示へ変換します。
    /// - Parameter series: 整形するPID系列。
    /// - Returns: 最小、平均、最大を単位付きで示す文字列。
    private func statisticsText(_ series: SessionPIDSeries) -> String {
        String(
            format: String(localized: "analysis.components.statistics"),
            locale: .autoupdatingCurrent,
            series.latestValue,
            series.minimumValue,
            series.averageValue,
            series.maximumValue,
            series.unit
        )
    }

    /// PID識別子を16進表現へ変換します。
    ///
    /// 責務: 1件のService/PIDをローカライズ可能な表示識別子へ変換します。
    /// - Parameters:
    ///   - service: OBD Service番号。
    ///   - pid: Service内PID番号。
    /// - Returns: ServiceとPIDを16進表記した文字列。
    private func pidLabel(service: UInt8, pid: UInt8) -> String {
        String(format: String(localized: "analysis.pid.identifier"), locale: .autoupdatingCurrent, service, pid)
    }

    /// 接続履歴画面と同じ抑制された奥行きを与える背景です。
    private var background: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            RadialGradient(colors: [Color.accentColor.opacity(0.075), .clear], center: .topTrailing, startRadius: 0, endRadius: 620 * metrics.scale)
        }
    }
}
#endif
