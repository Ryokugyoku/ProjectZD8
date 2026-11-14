#if os(iOS)
import SwiftUI

/// iPhone向けに進行中セッションと車両別アーカイブを描画します。
struct IOSConnectionHistoryView: View {
    /// LogHistoryが提供する現在の履歴状態です。
    let state: ConnectionHistoryState
    /// 履歴の型付き操作をApplicationへ通知します。
    let send: (ConnectionHistoryAction) -> Void

    /// 現在表示中のPID時系列解析状態です。
    let analysisState: SessionLogAnalysisState
    /// PID時系列解析操作をApplicationへ通知します。
    let sendAnalysis: (SessionLogAnalysisAction) -> Void

    /// iOSの alert 構成です。アップロード失敗には再試行ボタンを置きます。
    private let alertFactory = ConnectionHistoryAlertFactory()
    /// alert 本文のRaw件数と容量を整形します。
    private let rawSummaryFormatter = ConnectionHistoryRawSummaryMessageFormatter()
    /// 履歴の距離・時間表示を整形します。
    private let measurementFormatter = ConnectionHistoryMeasurementFormatter()
    /// セッションと車両の表示文言を整形します。
    private let textFormatter = ConnectionHistorySessionTextFormatter()
    /// セッション操作の表示可否を判定します。
    private let actionPolicy = ConnectionHistorySessionActionPolicy()

    /// iPhone向けの階層化された接続履歴と詳細導線を提供します。
    ///
    /// 責務: 接続履歴状態を進行中表示と車両別アーカイブへ分けて描画します。
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    hero
                    if state.phase == .failed {
                        failureState
                    } else if state.sessions.isEmpty {
                        emptyState
                    } else {
                        activeSection
                        vehicleArchiveSection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .navigationDestination(for: ConnectionHistoryVehicleGroupID.self) { id in
                vehicleSessionList(for: id)
            }
            .navigationDestination(for: ConnectionSessionID.self) { id in
                if let session = state.sessions.first(where: { $0.id == id }) {
                    IOSConnectionSessionDetailView(
                        session: session,
                        send: send,
                        analysisState: analysisState,
                        sendAnalysis: sendAnalysis,
                        isDeleting: state.deletingSessionID == session.id
                    )
                }
            }
            .refreshable { send(.refreshRequested) }
            .accessibilityIdentifier("ios-connection-history")
        }
        .actionAlerts(
            ConnectionHistoryAlertKind.allCases.map { alertFactory.alert($0, in: state) },
            send: send,
            message: alertMessage
        )
    }

    /// alert 本文の表示元を `Text` へ変換します。
    ///
    /// 責務: 1件の alert 本文をローカライズ文言またはRaw集計入りの警告文へ変換します。
    /// - Parameter message: Applicationが準備した alert 本文。
    /// - Returns: alert に表示する本文。
    private func alertMessage(_ message: ConnectionHistoryAlertMessage) -> Text {
        switch message {
        case let .localized(key):
            Text(LocalizedStringKey(key))
        case let .rawSummary(formatKey, recordCount, byteCount):
            Text(rawSummaryFormatter.text(formatKey: formatKey, recordCount: recordCount, byteCount: byteCount))
        }
    }

    /// 履歴総数と記録済み総走行時間を示す画面上部カードです。
    private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 58, height: 58)
                    .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text("history.eyebrow").font(.caption.weight(.bold)).tracking(1.4).foregroundStyle(.tint)
                    Text("history.title").font(.system(.largeTitle, design: .rounded, weight: .bold))
                    Text("history.subtitle").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 10) {
                summaryPill(value: "\(state.sessions.count)", titleKey: "history.summary.total", color: .primary)
                summaryPill(value: measurementFormatter.durationText(state.totalRecordedDuration), titleKey: "history.summary.duration", color: .cyan)
            }
        }
        .padding(22)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.primary.opacity(0.08)) }
    }

    /// 進行中セッションを終了済みアーカイブから分離して表示します。
    @ViewBuilder private var activeSection: some View {
        if !state.activeSessions.isEmpty {
            sectionTitle("history.active.title", systemImage: "dot.radiowaves.left.and.right")
            ForEach(state.activeSessions) { session in activeSessionCard(session) }
        }
    }

    /// 終了済みセッションを車両単位のカードとして表示します。
    private var vehicleArchiveSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("history.archive.title", systemImage: "car.2.fill")
            if state.vehicleGroups.isEmpty {
                Text("history.archive.empty")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .padding(20).frame(maxWidth: .infinity)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else {
                ForEach(state.vehicleGroups) { group in
                    NavigationLink(value: group.id) { vehicleGroupCard(group) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("ios-history-vehicle-\(textFormatter.groupIdentifier(group.id))")
                }
            }
        }
    }

    /// 1件の進行中セッションを記録状態と自動更新経過時間で描画します。
    ///
    /// 責務: 1件の未終了セッションを接続中のライブカードへ変換します。
    /// - Parameter session: 表示する未終了セッション。
    /// - Returns: 記録状態、車両、開始時刻、経過時間を含むカード。
    private func activeSessionCard(_ session: ConnectionSession) -> some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(spacing: 12) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 20, weight: .semibold)).foregroundStyle(.green)
                    .frame(width: 46, height: 46).background(.green.opacity(0.13), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(textFormatter.vehicleName(session)).font(.system(.headline, design: .rounded, weight: .bold))
                    Text("history.active.recording").font(.caption.weight(.bold)).foregroundStyle(.green)
                }
                Spacer()
                Text(session.startedAt, style: .timer)
                    .font(.system(.title3, design: .monospaced, weight: .bold)).foregroundStyle(.green)
                    .accessibilityLabel(Text("history.active.elapsed"))
            }
            HStack {
                labeledDate("history.started", session.startedAt)
                Spacer()
                Text(textFormatter.shortID(session.id)).font(.caption.monospaced().weight(.semibold)).foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(
            LinearGradient(colors: [.green.opacity(0.12), Color.primary.opacity(0.035)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay { RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.green.opacity(0.28)) }
        .shadow(color: .green.opacity(0.10), radius: 18, y: 8)
    }

    /// 1台分の終了済み履歴集計を遷移可能なカードとして描画します。
    ///
    /// 責務: 1件の車両別履歴集計を件数、総時間、総走行距離と警告状態を持つカードへ変換します。
    /// - Parameter group: 表示する車両別履歴集計。
    /// - Returns: 車両情報、セッション件数、総時間、総走行距離、中断警告を含むカード。
    private func vehicleGroupCard(_ group: ConnectionHistoryVehicleGroup) -> some View {
        HStack(spacing: 14) {
            Image(systemName: group.interruptedCount > 0 ? "car.side.fill" : "car.side")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(group.interruptedCount > 0 ? Color.orange : Color.accentColor)
                .frame(width: 50, height: 50)
                .background(
                    (group.interruptedCount > 0 ? Color.orange : Color.accentColor).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 5) {
                Text(textFormatter.vehicleGroupName(group.vehicle))
                    .font(.system(.headline, design: .rounded, weight: .bold)).lineLimit(1)
                HStack(spacing: 3) {
                    Text(group.sessionCount, format: .number)
                    Text("history.vehicle.sessions")
                }
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        Label(measurementFormatter.durationText(group.totalDuration), systemImage: "clock")
                        Label(measurementFormatter.distanceText(group.totalDistanceKilometers), systemImage: "road.lanes")
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Label(measurementFormatter.durationText(group.totalDuration), systemImage: "clock")
                        Label(measurementFormatter.distanceText(group.totalDistanceKilometers), systemImage: "road.lanes")
                    }
                }
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 4)
            if group.interruptedCount > 0 {
                warningBadge(group.interruptedCount)
            }
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
        }
        .padding(17)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(group.interruptedCount > 0 ? .orange.opacity(0.25) : Color.primary.opacity(0.07))
        }
    }

    /// 選択車両の絞り込み可能な終了済みセッション一覧を描画します。
    ///
    /// 責務: 1台分の履歴へ複合絞り込みと並び替えを適用した一覧を描画します。
    /// - Parameter id: 表示する車両グループ識別子。
    /// - Returns: 絞り込み操作とセッション詳細導線を含む画面。
    private func vehicleSessionList(for id: ConnectionHistoryVehicleGroupID) -> some View {
        let group = state.vehicleGroups.first(where: { $0.id == id })
        let sessions = state.filteredSessions(for: id)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                vehicleListHeader(group)
                filterPanel
                if sessions.isEmpty { noFilterResults } else {
                    ForEach(sessions) { session in sessionListItem(session) }
                }
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .navigationTitle(textFormatter.vehicleGroupName(group?.vehicle))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// 車両別一覧の概要を表示します。
    ///
    /// 責務: 1件の車両グループを一覧上部の件数と警告概要へ変換します。
    /// - Parameter group: 表示する車両別履歴集計。
    /// - Returns: 車両別の総件数と中断件数を含む概要。
    @ViewBuilder private func vehicleListHeader(_ group: ConnectionHistoryVehicleGroup?) -> some View {
        if let group {
            ViewThatFits(in: .horizontal) {
                HStack {
                    summaryPill(value: "\(group.sessionCount)", titleKey: "history.summary.total", color: .primary)
                    summaryPill(value: measurementFormatter.durationText(group.totalDuration), titleKey: "history.summary.duration", color: .cyan)
                    summaryPill(value: measurementFormatter.distanceText(group.totalDistanceKilometers), titleKey: "history.summary.distance", color: .mint)
                    if group.interruptedCount > 0 { warningBadge(group.interruptedCount) }
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        summaryPill(value: "\(group.sessionCount)", titleKey: "history.summary.total", color: .primary)
                        if group.interruptedCount > 0 { warningBadge(group.interruptedCount) }
                    }
                    HStack {
                        summaryPill(value: measurementFormatter.durationText(group.totalDuration), titleKey: "history.summary.duration", color: .cyan)
                        summaryPill(value: measurementFormatter.distanceText(group.totalDistanceKilometers), titleKey: "history.summary.distance", color: .mint)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 日付範囲、終了理由、並び順を同時指定できる操作パネルです。
    private var filterPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("history.filter.title", systemImage: "line.3.horizontal.decrease.circle.fill")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                Spacer()
                if state.hasActiveFilters { Button("history.filter.reset") { send(.filtersReset) }.font(.caption.weight(.bold)) }
            }
            optionalDateRow(
                title: "history.filter.from",
                date: state.filterStartDate,
                fallback: state.closedSessions.map(\.startedAt).min() ?? .distantPast
            ) { send(.filterStartDateChanged($0)) }
            optionalDateRow(
                title: "history.filter.to",
                date: state.filterEndDate,
                fallback: state.closedSessions.map(\.startedAt).max() ?? .distantPast
            ) { send(.filterEndDateChanged($0)) }
            Picker("history.filter.reason", selection: Binding(get: { state.endReasonFilter }, set: { send(.endReasonFilterChanged($0)) })) {
                ForEach(ConnectionHistoryEndReasonFilter.allCases, id: \.self) { Text(endReasonFilterKey($0)).tag($0) }
            }
            Picker("history.sort.title", selection: Binding(get: { state.sortOrder }, set: { send(.sortOrderChanged($0)) })) {
                ForEach(ConnectionHistorySortOrder.allCases, id: \.self) { Text(sortOrderKey($0)).tag($0) }
            }
        }
        .pickerStyle(.menu)
        .padding(17)
        .background(Color.accentColor.opacity(0.065), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    /// 任意の日付条件を有効化できる1行として描画します。
    ///
    /// 責務: 1件の任意日付を有効化操作と日付選択操作へ変換します。
    /// - Parameters:
    ///   - title: 日付条件のローカライズキー。
    ///   - date: 現在選択中の日付。
    ///   - fallback: 有効化時に使う履歴由来の初期日。
    ///   - update: 変更後の日付通知先。
    /// - Returns: 有効化スイッチと日付選択欄を含む行。
    private func optionalDateRow(
        title: LocalizedStringKey,
        date: Date?,
        fallback: Date,
        update: @escaping (Date?) -> Void
    ) -> some View {
        HStack {
            Toggle(title, isOn: Binding(get: { date != nil }, set: { update($0 ? fallback : nil) }))
            if let date {
                DatePicker("", selection: Binding(get: { date }, set: { update($0) }), displayedComponents: .date).labelsHidden()
            }
        }
    }

    /// 1件の終了済みセッションを詳細遷移行として描画します。
    ///
    /// 責務: 1件の終了済みセッションを日時、時間、走行距離、終了理由を持つ一覧行へ変換します。
    /// - Parameter session: 表示する終了済みセッション。
    /// - Returns: 詳細画面へ遷移可能なセッション行。
    private func sessionRow(_ session: ConnectionSession) -> some View {
        HStack(spacing: 13) {
            if session.status == .completed {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
                    .font(.title3)
            } else {
                WarningTriangleIcon(size: 19)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(session.startedAt, format: .dateTime.year().month().day().hour().minute())
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                Text(LocalizedStringKey(textFormatter.endReasonKey(session.endReason)))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(session.status == .completed ? Color.secondary : Color.orange)
                Label(textFormatter.acquisitionDeviceText(session), systemImage: "laptopcomputer.and.iphone")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    cloudStatusBadge(session)
                    localStatusBadge(session)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Label(measurementFormatter.durationText(measurementFormatter.sessionDuration(session)), systemImage: "clock")
                Label(measurementFormatter.distanceText(session.recordedDistanceKilometers), systemImage: "road.lanes")
            }
            .font(.caption2.monospacedDigit().weight(.semibold))
            .foregroundStyle(.secondary)
            Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
        }
        .padding(15)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// 1件のセッション行へ詳細導線、必要なアップロード、端末容量解放操作を配置します。
    ///
    /// 責務: 1件の終了済みセッションを詳細遷移と現在の保管状態に必要な単一操作へ変換します。
    /// - Parameter session: 表示する終了済みセッション。
    /// - Returns: 状態表示、詳細導線、必要に応じた容量解放ボタンを含むカード。
    private func sessionListItem(_ session: ConnectionSession) -> some View {
        VStack(spacing: 0) {
            NavigationLink(value: session.id) { sessionRow(session) }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ios-history-session-\(session.id.rawValue.uuidString)")
            if state.isManualUploadAvailable(for: session) {
                Divider().padding(.horizontal, 15)
                uploadAction(session)
            }
            if actionPolicy.canReleaseRawCache(session) {
                Divider().padding(.horizontal, 15)
                Button {
                    send(.localRawRemovalRequested(session.id))
                } label: {
                    Label("history.raw.remove.button", systemImage: "externaldrive.badge.minus")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.orange)
                .accessibilityIdentifier("ios-history-release-raw-\(session.id.rawValue.uuidString)")
            }
        }
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// 1件のセッションに現在必要なアップロード操作を表示します。
    ///
    /// 責務: 1件の手動送信可能なセッションを通常アップロード、再試行、進捗のいずれかの操作表示へ変換します。
    /// - Parameter session: アップロード操作を表示する接続セッション。
    /// - Returns: 現在の転送状態に対応するアップロード操作。
    @ViewBuilder private func uploadAction(_ session: ConnectionSession) -> some View {
        Button {
            send(.sessionUploadRequested(session.id))
        } label: {
            if state.uploadingSessionID == session.id {
                VStack(spacing: 6) {
                    ProgressView(value: state.uploadProgress ?? 0, total: 1)
                        .progressViewStyle(.linear)
                    HStack {
                        Text("history.upload.in_progress")
                        Spacer()
                        Text(state.uploadProgress ?? 0, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                    }
                    .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 15)
                .padding(.vertical, 10)
            } else if session.rawLogSummary.cloudState == .failed {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(.red, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("history.upload.retry")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                        Text("history.upload.retry.description")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.red)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 15)
                .padding(.vertical, 11)
                .background(.red.opacity(0.055))
            } else {
                Label("history.upload.button", systemImage: "icloud.and.arrow.up")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .foregroundStyle(.tint)
            }
        }
        .buttonStyle(.plain)
        .disabled(state.uploadingSessionID != nil)
        .accessibilityIdentifier("ios-history-upload-\(session.id.rawValue.uuidString)")
    }

    /// セッションのiCloud転送状態を一覧用バッジとして描画します。
    ///
    /// 責務: 1件のCloudKit転送状態をアイコン、文言、色を持つバッジへ変換します。
    /// - Parameter session: 表示対象の接続セッション。
    /// - Returns: iCloud転送状態バッジ。
    private func cloudStatusBadge(_ session: ConnectionSession) -> some View {
        rawStatusBadge(ConnectionHistoryRawStatusBadge(cloudState: session.rawLogSummary.cloudState))
    }

    /// セッションのRaw取得状態を一覧用バッジとして描画します。
    ///
    /// 責務: 1件のローカルRaw状態をダウンロード状態のアイコンと文言へ変換します。
    /// - Parameter session: 表示対象の接続セッション。
    /// - Returns: Rawダウンロード状態バッジ。
    private func localStatusBadge(_ session: ConnectionSession) -> some View {
        rawStatusBadge(ConnectionHistoryRawStatusBadge(localState: session.rawLogSummary.localState))
    }

    /// 共通のRaw状態バッジをiOSの一覧バッジとして描画します。
    ///
    /// 責務: 1件のバッジ内容をアイコン、文言、トーン色を持つラベルへ変換します。
    /// - Parameter badge: 表示するバッジ内容。
    /// - Returns: Raw状態バッジ。
    private func rawStatusBadge(_ badge: ConnectionHistoryRawStatusBadge) -> some View {
        Label(LocalizedStringKey(badge.titleKey), systemImage: badge.systemImage)
            .font(.caption2.weight(.bold))
            .foregroundStyle(badge.tone.color)
    }

    /// 絞り込み結果が空であることを表示します。
    private var noFilterResults: some View {
        ContentUnavailableView("history.filter.empty", systemImage: "magnifyingglass", description: Text("history.filter.empty.body"))
            .frame(maxWidth: .infinity).padding(.vertical, 30)
    }

    /// 履歴が存在しないことを表示します。
    private var emptyState: some View {
        ContentUnavailableView("history.empty.title", systemImage: "road.lanes", description: Text("history.empty.body"))
            .padding(30).frame(maxWidth: .infinity)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    /// 履歴保存先を利用できない状態と再試行操作を示します。
    private var failureState: some View {
        VStack(spacing: 14) {
            Image(systemName: "externaldrive.badge.exclamationmark").font(.system(size: 32)).foregroundStyle(.orange)
            Text("history.error.storage").font(.headline).multilineTextAlignment(.center)
            Button("history.error.retry") { send(.refreshRequested) }.buttonStyle(.borderedProminent)
        }
        .padding(28).frame(maxWidth: .infinity)
        .background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    /// セクションのローカライズ見出しを生成します。
    ///
    /// 責務: 1件の見出しキーとシンボルを履歴セクション見出しへ変換します。
    /// - Parameters:
    ///   - title: 見出しのローカライズキー。
    ///   - systemImage: 見出しを補助するSF Symbol名。
    /// - Returns: 履歴セクション用見出し。
    private func sectionTitle(_ title: LocalizedStringKey, systemImage: String) -> some View {
        Label(title, systemImage: systemImage).font(.system(.title3, design: .rounded, weight: .bold)).padding(.horizontal, 2)
    }

    /// 文字列集計値を要約ピルとして描画します。
    ///
    /// 責務: 1件の集計値を短い見出し付き要約へ変換します。
    /// - Parameters:
    ///   - value: 表示値。
    ///   - titleKey: 値の意味を示すキー。
    ///   - color: 値の表示色。
    /// - Returns: 値と見出しを含む要約ピル。
    private func summaryPill(value: String, titleKey: LocalizedStringKey, color: Color) -> some View {
        HStack(spacing: 7) {
            Text(value).font(.headline.monospacedDigit()).foregroundStyle(color)
            Text(titleKey).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }
            .padding(.horizontal, 13).padding(.vertical, 9).background(Color.primary.opacity(0.055), in: Capsule())
    }

    /// 中断件数を注意バッジとして描画します。
    ///
    /// 責務: 1件の中断件数を色とシンボルを併用した警告へ変換します。
    /// - Parameter count: 表示する中断件数。
    /// - Returns: 中断を示す警告バッジ。
    private func warningBadge(_ count: Int) -> some View {
        HStack(spacing: 4) {
            WarningTriangleIcon(size: 11)
            Text("\(count)")
        }
            .font(.caption.weight(.bold)).foregroundStyle(.orange)
            .padding(.horizontal, 9).padding(.vertical, 6).background(.orange.opacity(0.11), in: Capsule())
            .accessibilityLabel(Text("history.warning.interrupted"))
            .accessibilityValue(Text(count, format: .number))
    }

    /// 日時を短い見出しとともに描画します。
    ///
    /// 責務: 1件の日時を履歴カード用の見出し付き表示へ変換します。
    /// - Parameters:
    ///   - title: 日時の意味を示すキー。
    ///   - date: 表示する日時。
    /// - Returns: 見出しと日時を含む表示。
    private func labeledDate(_ title: LocalizedStringKey, _ date: Date) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
            Text(date, format: .dateTime.month().day().hour().minute()).font(.caption.monospacedDigit().weight(.semibold))
        }
    }

    /// 終了理由条件の表示キーを返します。
    ///
    /// 責務: 1件の終了理由条件をPicker用ローカライズキーへ変換します。
    /// - Parameter filter: 表示する終了理由条件。
    /// - Returns: 条件名のローカライズキー。
    private func endReasonFilterKey(_ filter: ConnectionHistoryEndReasonFilter) -> LocalizedStringKey { LocalizedStringKey(filter.historyLocalizationKey) }

    /// 並び順の表示キーを返します。
    ///
    /// 責務: 1件の並び順をPicker用ローカライズキーへ変換します。
    /// - Parameter order: 表示する並び順。
    /// - Returns: 並び順名のローカライズキー。
    private func sortOrderKey(_ order: ConnectionHistorySortOrder) -> LocalizedStringKey { LocalizedStringKey(order.historyLocalizationKey) }
}
#endif
