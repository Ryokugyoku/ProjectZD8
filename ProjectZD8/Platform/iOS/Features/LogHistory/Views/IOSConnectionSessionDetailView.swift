#if os(iOS)
import SwiftUI

/// iPhone向けに選択セッションのRawログ保管とMac連携状態を描画します。
struct IOSConnectionSessionDetailView: View {
    /// 表示対象の接続セッションです。
    let session: ConnectionSession
    /// LogHistoryの型付き操作をApplicationへ通知します。
    let send: (ConnectionHistoryAction) -> Void
    /// 現在表示中のPID時系列解析状態です。
    let analysisState: SessionLogAnalysisState
    /// PID時系列解析操作をApplicationへ通知します。
    let sendAnalysis: (SessionLogAnalysisAction) -> Void

    /// Rawログの来歴と安全なローカル除去導線を提供します。
    ///
    /// 責務: 1件の接続セッションをiPhone、Cloud、Macの保管状態へ分けて描画します。
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero
                stopReviewCard
                rawMetrics
                storageJourney
                macReceiptCard
                analysisAction
                localRemovalAction
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .background(background)
        .navigationTitle("history.detail.title")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("ios-connection-session-detail")
    }

    /// 観測済み停止理由とユーザー確認状態を表示します。
    @ViewBuilder private var stopReviewCard: some View {
        if session.needsStopReview {
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 10) {
                    WarningTriangleIcon(size: 19)
                    Text("history.stop_review.card.title")
                        .font(.headline)
                }
                Text(stopReviewCardMessageKey)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("history.stop_review.card.action") {
                    send(.stopReviewRequested(session.id))
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(17)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.orange.opacity(0.22)) }
        } else if session.stopReviewDecision == .userInitiated {
            Label("history.stop_review.accepted", systemImage: "checkmark.seal.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)
                .padding(15)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    /// 観測済み終了理由に対応する詳細カード本文です。
    private var stopReviewCardMessageKey: LocalizedStringKey {
        session.endReason == .vehicleNoResponse
            ? "history.stop_review.card.no_response"
            : "history.stop_review.card.connection_lost"
    }

    /// 静的性能解析画面への遷移操作を表示します。
    private var analysisAction: some View {
        NavigationLink {
            IOSSessionLogAnalysisView(session: session, state: analysisState, send: sendAnalysis)
        } label: {
            HStack(spacing: 13) {
                Image(systemName: "chart.xyaxis.line")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.indigo)
                    .frame(width: 44, height: 44)
                    .background(Color.indigo.opacity(0.11), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("analysis.open").font(.headline)
                    Text("analysis.open.hint").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.indigo.opacity(0.16)) }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ios-history-open-analysis")
    }

    /// セッションの車両、日時、Rawログ概念を示す主カードです。
    private var hero: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("history.raw.badge")
                        .font(.caption.weight(.bold))
                        .tracking(1.5)
                        .foregroundStyle(.tint)
                    Text(session.vehicle?.name ?? String(localized: "history.vehicle.pending"))
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    Text(session.startedAt, format: .dateTime.year().month().day().hour().minute())
                        .font(.subheadline.monospaced().weight(.semibold))
                        .foregroundStyle(.secondary)
                    Label(acquisitionDeviceText, systemImage: "laptopcomputer.and.iphone")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 16)
                VStack(spacing: 8) {
                    if let modelCode = session.distanceSourceModelCode {
                        VehicleModelBadge(modelCode: modelCode)
                    }
                    Image(systemName: "waveform.path.ecg.rectangle.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.tint)
                        .frame(width: 66, height: 66)
                        .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }
            Text("history.raw.subtitle")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Text(session.id.rawValue.uuidString.uppercased())
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.primary.opacity(0.08)) }
    }

    /// Rawログ件数、容量、時刻精度を表示します。
    private var rawMetrics: some View {
        HStack(spacing: 10) {
            metric(
                value: session.rawLogSummary.recordCount.formatted(),
                titleKey: "history.raw.records",
                systemImage: "number",
                color: .cyan
            )
            metric(
                value: byteCountText(session.rawLogSummary.byteCount),
                titleKey: "history.raw.bytes",
                systemImage: "externaldrive.fill",
                color: .blue
            )
            metric(
                value: "ms",
                titleKey: "history.raw.precision",
                systemImage: "timer",
                color: .indigo
            )
        }
    }

    /// iPhone、Cloud、Macの保管状態を順序付きで表示します。
    private var storageJourney: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("history.raw.storage.title")
                .font(.system(.headline, design: .rounded, weight: .bold))
            journeyRow(
                titleKey: "history.raw.storage.iphone",
                statusKey: localStateKey,
                systemImage: "iphone.gen3",
                color: localStateColor
            )
            journeyRow(
                titleKey: "history.raw.storage.cloud",
                statusKey: cloudStateKey,
                systemImage: "icloud.fill",
                color: cloudStateColor
            )
            journeyRow(
                titleKey: "history.raw.storage.mac",
                statusKey: session.rawLogSummary.isDurablyImportedByMac
                    ? "history.raw.mac.verified"
                    : "history.raw.mac.pending",
                systemImage: "desktopcomputer",
                color: session.rawLogSummary.isDurablyImportedByMac ? .green : .orange
            )
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.primary.opacity(0.08)) }
    }

    /// Mac取込受領証または未確認状態を表示します。
    private var macReceiptCard: some View {
        HStack(spacing: 15) {
            Image(systemName: session.rawLogSummary.isDurablyImportedByMac ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(session.rawLogSummary.isDurablyImportedByMac ? Color.green : Color.orange)
                .frame(width: 52, height: 52)
                .background(
                    (session.rawLogSummary.isDurablyImportedByMac ? Color.green : Color.orange).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 4) {
                Text("history.raw.mac.receipt")
                    .font(.headline)
                if let receipt = session.rawLogSummary.macImportReceipt,
                   session.rawLogSummary.isDurablyImportedByMac {
                    Text(receipt.deviceName)
                        .font(.subheadline.weight(.semibold))
                    Text(receipt.importedAt, format: .dateTime.year().month().day().hour().minute())
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                } else {
                    Text("history.raw.mac.receipt_missing")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    /// iPhoneにRawログがある終了済みセッションへローカル除去操作を表示します。
    @ViewBuilder private var localRemovalAction: some View {
        if session.endedAt != nil, session.rawLogSummary.localState == .available {
            Button(role: .destructive) {
                send(.localRawRemovalRequested(session.id))
            } label: {
                Label("history.raw.remove.button", systemImage: "iphone.slash")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red.opacity(0.88))
            .controlSize(.large)
            .accessibilityIdentifier("ios-history-remove-local-raw")
        } else if session.rawLogSummary.localState == .removed {
            Label("history.raw.remove.completed", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(18)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    /// 1件のRawログ集計値をコンパクトなカードとして描画します。
    ///
    /// 責務: 1件の集計値をアイコン、値、見出しを持つiPhoneカードへ変換します。
    /// - Parameters:
    ///   - value: 強調表示する集計値。
    ///   - titleKey: ローカライズ済み見出しキー。
    ///   - systemImage: 集計概念を示すSF Symbol。
    ///   - color: 集計カードのアクセント色。
    /// - Returns: 固定幅を共有する集計カード。
    private func metric(value: String, titleKey: LocalizedStringKey, systemImage: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage).foregroundStyle(color)
            Text(value).font(.system(.headline, design: .rounded, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
            Text(titleKey).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 19, style: .continuous).stroke(color.opacity(0.16)) }
    }

    /// 1段階の保管先と状態を描画します。
    ///
    /// 責務: 1件の保管先状態をアイコンと状態ラベルを持つ行へ変換します。
    /// - Parameters:
    ///   - titleKey: 保管先のローカライズキー。
    ///   - statusKey: 現在状態のローカライズキー。
    ///   - systemImage: 保管先を示すSF Symbol。
    ///   - color: 現在状態のアクセント色。
    /// - Returns: 保管先、状態、進行線を含む表示行。
    private func journeyRow(
        titleKey: LocalizedStringKey,
        statusKey: LocalizedStringKey,
        systemImage: String,
        color: Color
    ) -> some View {
        HStack(spacing: 13) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 42, height: 42)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text(titleKey).font(.subheadline.weight(.semibold))
            Spacer()
            Text(statusKey)
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(color.opacity(0.10), in: Capsule())
        }
    }

    /// Rawログのバイト数を現在Locale向けの容量表現へ変換します。
    ///
    /// 責務: 1件の非負バイト数をユーザー向けファイル容量文字列へ変換します。
    /// - Parameter bytes: Raw Payload合計バイト数。
    /// - Returns: 現在Localeへ整形した容量文字列。
    private func byteCountText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, bytes), countStyle: .file)
    }

    /// 表示中セッションの取得元端末をプラットフォーム付き表示名へ変換します。
    private var acquisitionDeviceText: String {
        guard let device = session.acquisitionDevice else {
            return String(localized: "history.device.unknown")
        }
        return "\(device.name) (\(device.platform.rawValue))"
    }

    /// 現在端末のRaw保管状態に対応するローカライズキーです。
    private var localStateKey: LocalizedStringKey {
        switch session.rawLogSummary.localState {
        case .empty: "history.raw.local.empty"
        case .available: "history.raw.local.available"
        case .removed: "history.raw.local.removed"
        }
    }

    /// 現在端末のRaw保管状態に対応する色です。
    private var localStateColor: Color {
        switch session.rawLogSummary.localState {
        case .empty: .secondary
        case .available: .blue
        case .removed: .gray
        }
    }

    /// CloudKit転送状態に対応するローカライズキーです。
    private var cloudStateKey: LocalizedStringKey {
        switch session.rawLogSummary.cloudState {
        case .notUploaded: "history.raw.cloud.not_uploaded"
        case .pending: "history.raw.cloud.pending"
        case .uploaded: "history.raw.cloud.uploaded"
        case .failed: "history.raw.cloud.failed"
        }
    }

    /// CloudKit転送状態に対応する色です。
    private var cloudStateColor: Color {
        switch session.rawLogSummary.cloudState {
        case .notUploaded: .secondary
        case .pending: .orange
        case .uploaded: .cyan
        case .failed: .red
        }
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
