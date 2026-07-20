#if os(iOS)
import SwiftUI

/// iPhone向けに保存済みPID時系列を静的な性能解析として描画します。
struct IOSSessionLogAnalysisView: View {
    /// 表示するセッションです。
    let session: ConnectionSession
    /// Analysisが提供する時系列解析状態です。
    let state: SessionLogAnalysisState
    /// Analysisの型付き操作をApplicationへ通知します。
    let send: (SessionLogAnalysisAction) -> Void
    /// 現在の画面を閉じてセッション詳細へ戻します。
    @Environment(\.dismiss) private var dismiss

    /// セッションのPID性能解析を提供します。
    ///
    /// 責務: 1件のセッション解析状態をiPhone向けの静的性能解析画面へ変換します。
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                hero
                summary
                timeline
            }
            .padding(20)
        }
        .background(background)
        .navigationTitle("analysis.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("analysis.back.session") { send(.dismissed); dismiss() } } }
        .onAppear { if state.sessionID != session.id { send(.sessionSelected(session.id)) } }
        .accessibilityIdentifier("ios-session-log-analysis")
    }

    /// セッションの解析対象と不変な表示概念を示す主カードです。
    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("analysis.eyebrow", systemImage: "gauge.with.dots.needle.67percent")
                .font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(.white.opacity(0.76))
            Text(session.vehicle?.name ?? String(localized: "history.vehicle.pending"))
                .font(.system(.largeTitle, design: .rounded, weight: .bold)).foregroundStyle(.white)
            Text(session.startedAt, format: .dateTime.year().month().day().hour().minute().second())
                .font(.caption.monospaced().weight(.semibold)).foregroundStyle(.white.opacity(0.70))
            Text("analysis.hero.caption").font(.subheadline).foregroundStyle(.white.opacity(0.84))
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(24)
        .background(LinearGradient(colors: [.indigo, .blue.opacity(0.88), .cyan.opacity(0.66)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    /// 解析件数と変換成否を表示します。
    private var summary: some View {
        HStack(spacing: 10) {
            metric(value: state.timeline.count.formatted(), key: "analysis.summary.samples", symbol: "waveform.path.ecg", color: .cyan)
            metric(value: state.decodedSampleCount.formatted(), key: "analysis.summary.decoded", symbol: "function", color: .green)
            metric(value: state.rawOnlySampleCount.formatted(), key: "analysis.summary.raw", symbol: "shippingbox", color: .orange)
        }
    }

    /// 全PIDの観測順表示または読込状態を描画します。
    @ViewBuilder private var timeline: some View {
        if state.phase == .loading && state.timeline.isEmpty { ProgressView("analysis.loading").frame(maxWidth: .infinity).padding(28) }
        else if state.phase == .failed && state.timeline.isEmpty { Label("analysis.error.storage", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).padding(20) }
        else if state.phase == .loaded && state.timeline.isEmpty { ContentUnavailableView("analysis.empty.title", systemImage: "waveform.slash", description: Text("analysis.empty.body")) }
        else {
            LazyVStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("analysis.timeline.title").font(.system(.title3, design: .rounded, weight: .bold))
                    Spacer()
                    if state.phase == .loading { ProgressView().controlSize(.small) }
                }
                Text("analysis.timeline.subtitle").font(.caption).foregroundStyle(.secondary)
                if state.phase == .loading { analysisProgress }
                ForEach(state.timeline) { sample in sampleRow(sample) }
            }
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

    /// 1件のPIDを値、Raw根拠、時刻とともに描画します。
    ///
    /// 責務: 1件の解析PIDサンプルを時刻と変換来歴を持つiPhone行へ変換します。
    /// - Parameter sample: 描画する時系列PIDサンプル。
    /// - Returns: 数値化済み値またはRaw根拠を持つ解析行。
    private func sampleRow(_ sample: SessionLogAnalysisState.TimelineSample) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(sample.nameKey.map { String(localized: String.LocalizationValue($0)) } ?? pidLabel(sample)).font(.subheadline.weight(.bold))
                    Text(pidLabel(sample)).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                Spacer()
                if let value = sample.value { Text(value.formatted(.number.precision(.fractionLength(0...2))) + " " + (sample.unit ?? "")).font(.system(.headline, design: .rounded, weight: .bold)).foregroundStyle(.tint) }
                else { Text("analysis.raw.unavailable").font(.caption.weight(.bold)).foregroundStyle(.orange) }
            }
            HStack { Text(sample.observedAt, format: .dateTime.hour().minute().second().secondFraction(.fractional(3))).font(.caption.monospaced()).foregroundStyle(.secondary); Spacer(); Text(payloadHex(sample.payload)).font(.caption.monospaced()).foregroundStyle(.secondary) }
        }
        .padding(15).background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// 集計値をコンパクトなカードへ変換します。
    ///
    /// 責務: 1件の解析集計をアイコンと数値を持つiPhoneカードへ変換します。
    private func metric(value: String, key: LocalizedStringKey, symbol: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) { Image(systemName: symbol).foregroundStyle(color); Text(value).font(.headline.weight(.bold)); Text(key).font(.caption2).foregroundStyle(.secondary) }
            .padding(13).frame(maxWidth: .infinity, alignment: .leading).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// PID識別子を16進表現へ変換します。
    ///
    /// 責務: 1件のService/PIDを安定した表示識別子へ変換します。
    private func pidLabel(_ sample: SessionLogAnalysisState.TimelineSample) -> String { String(format: String(localized: "analysis.pid.identifier"), locale: .autoupdatingCurrent, sample.service, sample.pid) }
    /// Payloadを検証可能な16進表現へ変換します。
    ///
    /// 責務: 1件のRaw Payloadを短い16進来歴文字列へ変換します。
    private func payloadHex(_ payload: [UInt8]) -> String { payload.map { String(format: "%02X", $0) }.joined(separator: " ") }
    /// 画面に抑制された奥行きを与えます。
    private var background: some View { ZStack { Color(uiColor: .systemGroupedBackground); RadialGradient(colors: [.cyan.opacity(0.10), .clear], center: .topTrailing, startRadius: 0, endRadius: 480) }.ignoresSafeArea() }
}
#endif
