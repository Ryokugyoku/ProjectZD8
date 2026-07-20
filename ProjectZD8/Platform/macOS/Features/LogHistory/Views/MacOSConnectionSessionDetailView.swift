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
    /// 表示対象を全端末から削除している途中かを示します。
    let isDeleting: Bool
    /// 車両セッション一覧へ戻る一時的な画面遷移操作です。
    let back: () -> Void

    /// 車両別学習データの来歴と保管状態を提供します。
    ///
    /// 責務: 1件の接続セッションをMac保管済みRawログと車両別学習準備へ分けて描画します。
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20 * metrics.scale) {
                detailActions
                hero
                HStack(alignment: .top, spacing: 16 * metrics.scale) {
                    rawDataCard
                    analysisCard
                    integrityCard
                }
                trainingCard
                lineageCard
            }
            .padding(28 * metrics.scale)
        }
        .background(background)
        .navigationTitle("history.detail.title")
        .accessibilityIdentifier("macos-connection-session-detail")
    }

    /// 車両スコープ枠を置き換える静的性能解析カードです。
    private var analysisCard: some View {
        NavigationLink {
            MacOSSessionLogAnalysisView(session: session, state: analysisState, send: sendAnalysis, metrics: metrics, back: { })
        } label: {
            statusCard(
                titleKey: "analysis.open",
                value: String(localized: "analysis.card.value"),
                caption: analysisCardCaption,
                systemImage: "gauge.with.dots.needle.67percent",
                color: .indigo
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("macos-history-open-analysis")
    }

    /// 車両セッション一覧へ戻る操作と全端末削除操作を表示します。
    private var detailActions: some View {
        HStack(spacing: 12 * metrics.scale) {
            Button(action: back) {
                Label("history.detail.back", systemImage: "chevron.left")
                    .font(.system(size: 13 * metrics.scale, weight: .semibold))
                    .frame(minHeight: 32 * metrics.scale)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("macos-history-session-back")
            Spacer()
            if session.endedAt != nil {
                Button(role: .destructive) {
                    send(.sessionDeletionRequested(session.id))
                } label: {
                    if isDeleting {
                        ProgressView()
                            .controlSize(.small)
                            .frame(minWidth: 128 * metrics.scale, minHeight: 32 * metrics.scale)
                    } else {
                        Label("history.delete.button", systemImage: "trash")
                            .font(.system(size: 13 * metrics.scale, weight: .semibold))
                            .frame(minHeight: 32 * metrics.scale)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red.opacity(0.88))
                .disabled(isDeleting)
                .accessibilityIdentifier("macos-history-delete-session")
            }
        }
    }

    /// セッションの車両とRawログ保管状態を示す主カードです。
    private var hero: some View {
        HStack(spacing: 22 * metrics.scale) {
            Image(systemName: "waveform.path.ecg.rectangle.fill")
                .font(.system(size: 34 * metrics.scale, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 78 * metrics.scale, height: 78 * metrics.scale)
                .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 23 * metrics.scale, style: .continuous))
            VStack(alignment: .leading, spacing: 6 * metrics.scale) {
                Text("history.training.badge")
                    .font(.system(size: 10 * metrics.scale, weight: .bold, design: .rounded))
                    .tracking(1.8 * metrics.scale)
                    .foregroundStyle(.white.opacity(0.72))
                Text(session.vehicle?.name ?? String(localized: "history.vehicle.pending"))
                    .font(.system(size: 30 * metrics.scale, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(session.startedAt, format: .dateTime.year().month().day().hour().minute())
                    .font(.system(size: 12 * metrics.scale, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.72))
            }
            Spacer(minLength: 20 * metrics.scale)
            VStack(alignment: .trailing, spacing: 7 * metrics.scale) {
                Label(trainingStatusKey, systemImage: isTrainingReady ? "checkmark.seal.fill" : "clock.badge.exclamationmark")
                    .font(.system(size: 12 * metrics.scale, weight: .bold))
                    .foregroundStyle(isTrainingReady ? Color.green : Color.orange)
                    .padding(.horizontal, 13 * metrics.scale)
                    .padding(.vertical, 8 * metrics.scale)
                    .background(.black.opacity(0.20), in: Capsule())
                Text(session.id.rawValue.uuidString.uppercased())
                    .font(.system(size: 9 * metrics.scale, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.48))
                    .textSelection(.enabled)
            }
        }
        .padding(25 * metrics.scale)
        .background(
            LinearGradient(
                colors: [Color.indigo.opacity(0.96), Color.blue.opacity(0.85), Color.cyan.opacity(0.68)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28 * metrics.scale, style: .continuous)
        )
        .shadow(color: .blue.opacity(0.18), radius: 24 * metrics.scale, y: 10 * metrics.scale)
    }

    /// 未デコードRawログの件数と容量を表示します。
    private var rawDataCard: some View {
        statusCard(
            titleKey: "history.training.raw.title",
            value: session.rawLogSummary.recordCount.formatted(),
            caption: byteCountText(session.rawLogSummary.byteCount),
            systemImage: "cylinder.split.1x2.fill",
            color: .cyan
        )
    }

    /// ManifestとMac取込受領証の一致状態を表示します。
    private var integrityCard: some View {
        statusCard(
            titleKey: "history.training.integrity.title",
            value: session.rawLogSummary.isDurablyImportedByMac
                ? String(localized: "history.training.integrity.verified")
                : String(localized: "history.training.integrity.pending"),
            caption: digestCaption,
            systemImage: session.rawLogSummary.isDurablyImportedByMac ? "checkmark.shield.fill" : "shield.lefthalf.filled",
            color: session.rawLogSummary.isDurablyImportedByMac ? .green : .orange
        )
    }

    /// 車両単位の学習データ抽出準備を大きなカードで表示します。
    private var trainingCard: some View {
        HStack(spacing: 20 * metrics.scale) {
            ZStack {
                RoundedRectangle(cornerRadius: 22 * metrics.scale, style: .continuous)
                    .fill((isTrainingReady ? Color.green : Color.orange).opacity(0.13))
                Image(systemName: "brain.head.profile.fill")
                    .font(.system(size: 35 * metrics.scale, weight: .semibold))
                    .foregroundStyle(isTrainingReady ? Color.green : Color.orange)
            }
            .frame(width: 76 * metrics.scale, height: 76 * metrics.scale)
            VStack(alignment: .leading, spacing: 7 * metrics.scale) {
                Text("history.training.title")
                    .font(.system(size: 20 * metrics.scale, weight: .bold, design: .rounded))
                Text(isTrainingReady ? "history.training.ready.body" : "history.training.pending.body")
                    .font(.system(size: 13 * metrics.scale, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12 * metrics.scale)
            VStack(alignment: .trailing, spacing: 5 * metrics.scale) {
                Text("history.training.scope")
                    .font(.system(size: 9 * metrics.scale, weight: .bold))
                    .foregroundStyle(.tertiary)
                Text(session.vehicle == nil ? "—" : "VEHICLE / SESSION / SEQUENCE")
                    .font(.system(size: 10 * metrics.scale, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(22 * metrics.scale)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24 * metrics.scale, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24 * metrics.scale, style: .continuous)
                .stroke((isTrainingReady ? Color.green : Color.orange).opacity(0.22))
        }
    }

    /// Rawログが派生値から独立していることを示します。
    private var lineageCard: some View {
        HStack(spacing: 13 * metrics.scale) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 17 * metrics.scale, weight: .semibold))
                .foregroundStyle(.indigo)
            VStack(alignment: .leading, spacing: 3 * metrics.scale) {
                Text("history.training.lineage.title")
                    .font(.system(size: 12 * metrics.scale, weight: .bold))
                Text("history.training.lineage.body")
                    .font(.system(size: 11 * metrics.scale))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(17 * metrics.scale)
        .background(Color.indigo.opacity(0.07), in: RoundedRectangle(cornerRadius: 18 * metrics.scale, style: .continuous))
    }

    /// 1件の学習準備指標をカードとして描画します。
    ///
    /// 責務: 1件の指標を見出し、値、補足、アイコンを持つmacOSカードへ変換します。
    /// - Parameters:
    ///   - titleKey: 指標見出しのローカライズキー。
    ///   - value: 強調表示する値。
    ///   - caption: 値を補足する短い文字列。
    ///   - systemImage: 指標概念を示すSF Symbol。
    ///   - color: 指標のアクセント色。
    /// - Returns: 同じ高さで並べられる指標カード。
    private func statusCard(
        titleKey: LocalizedStringKey,
        value: String,
        caption: String,
        systemImage: String,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 13 * metrics.scale) {
            HStack {
                Image(systemName: systemImage).foregroundStyle(color)
                Text(titleKey).font(.system(size: 10 * metrics.scale, weight: .bold)).foregroundStyle(.secondary)
                Spacer()
            }
            Text(value)
                .font(.system(size: 19 * metrics.scale, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(caption)
                .font(.system(size: 9.5 * metrics.scale, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(18 * metrics.scale)
        .frame(maxWidth: .infinity, minHeight: 132 * metrics.scale, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 21 * metrics.scale, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 21 * metrics.scale, style: .continuous).stroke(color.opacity(0.15)) }
    }

    /// Rawログのバイト数を現在Locale向けの容量表現へ変換します。
    ///
    /// 責務: 1件の非負バイト数をユーザー向けファイル容量文字列へ変換します。
    /// - Parameter bytes: Raw Payload合計バイト数。
    /// - Returns: 現在Localeへ整形した容量文字列。
    private func byteCountText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, bytes), countStyle: .file)
    }

    /// 解析対象Rawログ件数をカード補足へ変換します。
    private var analysisCardCaption: String {
        String(
            format: String(localized: "analysis.card.caption"),
            locale: .autoupdatingCurrent,
            session.rawLogSummary.recordCount
        )
    }

    /// Manifest Digestを短縮した表示文字列です。
    private var digestCaption: String {
        guard let digest = session.rawLogSummary.manifestDigest else { return "—" }
        return String(digest.prefix(16)).uppercased()
    }

    /// 現在セッションを車両別学習抽出へ使用できるかを示します。
    private var isTrainingReady: Bool {
        session.vehicle != nil
            && session.rawLogSummary.localState == .available
            && session.rawLogSummary.recordCount > 0
            && session.rawLogSummary.isDurablyImportedByMac
    }

    /// 学習準備状態に対応するローカライズキーです。
    private var trainingStatusKey: LocalizedStringKey {
        isTrainingReady ? "history.training.ready" : "history.training.pending"
    }

    /// macOS詳細画面へ抑制された奥行きを与える背景です。
    private var background: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            RadialGradient(
                colors: [Color.indigo.opacity(0.085), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 620 * metrics.scale
            )
        }
    }
}
#endif
