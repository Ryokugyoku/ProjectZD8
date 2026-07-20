#if os(macOS)
import SwiftUI

/// macOS向けに保存済みPID時系列を静的な性能解析として描画します。
struct MacOSSessionLogAnalysisView: View {
    /// 表示するセッションです。
    let session: ConnectionSession
    /// Analysisが提供する時系列解析状態です。
    let state: SessionLogAnalysisState
    /// Analysisの型付き操作をApplicationへ通知します。
    let send: (SessionLogAnalysisAction) -> Void
    /// 現在のウインドウ寸法に対応する表示寸法です。
    let metrics: MacOSAppShellMetrics
    /// セッション詳細へ戻す操作です。
    let back: () -> Void
    /// NavigationStackの直前画面へ戻す環境操作です。
    @Environment(\.dismiss) private var dismiss

    /// セッションのPID性能解析を提供します。
    ///
    /// 責務: 1件のセッション解析状態をmacOS向けの静的性能解析画面へ変換します。
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18 * metrics.scale) {
                HStack { Button("analysis.back.session") { send(.dismissed); back(); dismiss() }.buttonStyle(.bordered); Spacer() }
                hero
                HStack(spacing: 12 * metrics.scale) { metric(state.timeline.count, "analysis.summary.samples", "waveform.path.ecg", .cyan); metric(state.decodedSampleCount, "analysis.summary.decoded", "function", .green); metric(state.rawOnlySampleCount, "analysis.summary.raw", "shippingbox", .orange) }
                timeline
            }
            .padding(28 * metrics.scale)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("analysis.title")
        .onAppear { if state.sessionID != session.id { send(.sessionSelected(session.id)) } }
        .accessibilityIdentifier("macos-session-log-analysis")
    }

    /// セッション解析の主題を示すカードです。
    private var hero: some View {
        HStack {
            VStack(alignment: .leading, spacing: 7 * metrics.scale) {
                Label("analysis.eyebrow", systemImage: "gauge.with.dots.needle.67percent").font(.system(size: 11 * metrics.scale, weight: .bold)).tracking(1.4 * metrics.scale).foregroundStyle(.white.opacity(0.76))
                Text(session.vehicle?.name ?? String(localized: "history.vehicle.pending")).font(.system(size: 30 * metrics.scale, weight: .bold, design: .rounded)).foregroundStyle(.white)
                Text(session.startedAt, format: .dateTime.year().month().day().hour().minute().second()).font(.system(size: 12 * metrics.scale, design: .monospaced)).foregroundStyle(.white.opacity(0.7))
            }
            Spacer(); Image(systemName: "waveform.path.ecg.rectangle.fill").font(.system(size: 42 * metrics.scale)).foregroundStyle(.white.opacity(0.9))
        }
        .padding(25 * metrics.scale).background(LinearGradient(colors: [.indigo, .blue.opacity(0.87), .cyan.opacity(0.64)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 28 * metrics.scale, style: .continuous))
    }

    /// 数値化件数を表示します。
    ///
    /// 責務: 1件の解析集計をアイコンと数値を持つmacOSカードへ変換します。
    /// - Parameters:
    ///   - value: 表示する集計件数。
    ///   - key: 集計見出しのローカライズキー。
    ///   - symbol: 集計概念を示すSF Symbol。
    ///   - color: 集計カードのアクセント色。
    /// - Returns: 同じ幅で並べられる解析集計カード。
    private func metric(_ value: Int, _ key: LocalizedStringKey, _ symbol: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8 * metrics.scale) { Image(systemName: symbol).foregroundStyle(color); Text(value.formatted()).font(.system(size: 24 * metrics.scale, weight: .bold, design: .rounded)); Text(key).font(.system(size: 11 * metrics.scale)).foregroundStyle(.secondary) }
            .padding(17 * metrics.scale).frame(maxWidth: .infinity, alignment: .leading).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20 * metrics.scale, style: .continuous))
    }

    /// PID時系列テーブルを描画します。
    @ViewBuilder private var timeline: some View {
        if state.phase == .loading && state.timeline.isEmpty { ProgressView("analysis.loading").frame(maxWidth: .infinity).padding(34 * metrics.scale) }
        else if state.phase == .failed && state.timeline.isEmpty { Label("analysis.error.storage", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
        else if state.phase == .loaded && state.timeline.isEmpty { ContentUnavailableView("analysis.empty.title", systemImage: "waveform.slash", description: Text("analysis.empty.body")) }
        else {
            LazyVStack(alignment: .leading, spacing: 8 * metrics.scale) {
                HStack {
                    Text("analysis.timeline.title").font(.system(size: 20 * metrics.scale, weight: .bold, design: .rounded))
                    Spacer()
                    if state.phase == .loading { ProgressView().controlSize(.small) }
                }
                Text("analysis.timeline.subtitle").font(.caption).foregroundStyle(.secondary)
                if state.phase == .loading { analysisProgress }
                ScrollView(.horizontal) {
                    LazyVStack(spacing: 0) {
                        analysisColumnHeader
                        Divider()
                        ForEach(state.timeline) { sample in analysisRow(sample) }
                    }
                    .frame(minWidth: 720 * metrics.scale)
                }
                .padding(18 * metrics.scale).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22 * metrics.scale, style: .continuous))
            }
        }
    }

    /// PID時系列の列見出しを表示します。
    private var analysisColumnHeader: some View {
        HStack(spacing: 18 * metrics.scale) {
            Text("analysis.column.time").frame(width: 105 * metrics.scale, alignment: .leading)
            Text("analysis.column.pid").frame(maxWidth: .infinity, alignment: .leading)
            Text("analysis.column.value").frame(width: 150 * metrics.scale, alignment: .leading)
            Text("analysis.column.raw").frame(width: 150 * metrics.scale, alignment: .leading)
        }
        .font(.caption.weight(.bold))
        .foregroundStyle(.secondary)
        .padding(.vertical, 8 * metrics.scale)
    }

    /// 1件のPIDサンプルを遅延生成可能な時系列行へ変換します。
    ///
    /// 責務: 1件のPIDサンプルを時刻、識別子、変換値、Raw根拠の4列へ変換します。
    /// - Parameter sample: 表示する時系列PIDサンプル。
    /// - Returns: 固定列幅を持つmacOS解析行。
    private func analysisRow(_ sample: SessionLogAnalysisState.TimelineSample) -> some View {
        HStack(spacing: 18 * metrics.scale) {
            Text(sample.observedAt, format: .dateTime.hour().minute().second().secondFraction(.fractional(3)))
                .font(.caption.monospaced())
                .frame(width: 105 * metrics.scale, alignment: .leading)
            VStack(alignment: .leading) {
                Text(sample.nameKey.map { String(localized: String.LocalizationValue($0)) } ?? pidLabel(sample)).font(.subheadline.weight(.semibold))
                Text(pidLabel(sample)).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(sample.value.map { $0.formatted(.number.precision(.fractionLength(0...2))) + " " + (sample.unit ?? "") } ?? String(localized: "analysis.raw.unavailable"))
                .foregroundStyle(sample.value == nil ? Color.orange : Color.accentColor)
                .frame(width: 150 * metrics.scale, alignment: .leading)
            Text(payloadHex(sample.payload))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 150 * metrics.scale, alignment: .leading)
        }
        .padding(.vertical, 9 * metrics.scale)
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

    /// PID識別子を16進表現へ変換します。
    ///
    /// 責務: 1件のService/PIDをローカライズ可能な表示識別子へ変換します。
    /// - Parameter sample: 識別子を表示するPIDサンプル。
    /// - Returns: ServiceとPIDを16進表記した文字列。
    private func pidLabel(_ sample: SessionLogAnalysisState.TimelineSample) -> String { String(format: String(localized: "analysis.pid.identifier"), locale: .autoupdatingCurrent, sample.service, sample.pid) }
    /// Payloadを検証可能な16進表現へ変換します。
    ///
    /// 責務: 1件のRaw Payloadを短い16進来歴文字列へ変換します。
    /// - Parameter payload: 表示する未加工応答バイト。
    /// - Returns: 空白区切りの16進バイト列。
    private func payloadHex(_ payload: [UInt8]) -> String { payload.map { String(format: "%02X", $0) }.joined(separator: " ") }
}
#endif
