#if os(macOS)
import SwiftUI

/// macOS向けに進行中セッションと車両別アーカイブをコックピット調で描画します。
struct MacOSConnectionHistoryView: View {
    /// 接続履歴内の車両一覧とセッション詳細を結ぶ一時的な画面遷移経路です。
    @State private var navigationState = MacOSConnectionHistoryNavigationState()

    /// LogHistoryが提供する現在の履歴状態です。
    let state: ConnectionHistoryState
    /// 履歴の型付き操作をApplicationへ通知します。
    let send: (ConnectionHistoryAction) -> Void
    /// 現在表示中のPID時系列解析状態です。
    let analysisState: SessionLogAnalysisState
    /// PID時系列解析操作をApplicationへ通知します。
    let sendAnalysis: (SessionLogAnalysisAction) -> Void
    /// 現在のウインドウサイズに対応する表示寸法です。
    let metrics: MacOSAppShellMetrics

    /// macOS向けの階層化された接続履歴と詳細導線を提供します。
    ///
    /// 責務: 接続履歴状態を進行中表示と車両別アーカイブへ分けて描画します。
    var body: some View {
        NavigationStack(path: $navigationState.path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20 * metrics.scale) {
                    hero
                    if state.phase == .failed {
                        failureState
                    } else if state.sessions.isEmpty {
                        emptyState
                    } else {
                        activeSection
                        archiveSection
                    }
                }
                .padding(26 * metrics.scale)
            }
            .background(historyBackground)
            .navigationDestination(for: MacOSConnectionHistoryRoute.self) { route in
                switch route {
                case let .vehicleSessions(id):
                    vehicleSessionList(for: id)
                case let .sessionDetail(id):
                    if let session = state.sessions.first(where: { $0.id == id }) {
                        MacOSConnectionSessionDetailView(
                            session: session,
                            metrics: metrics,
                            send: send,
                            analysisState: analysisState,
                            sendAnalysis: sendAnalysis,
                            isDeleting: state.deletingSessionID == session.id,
                            back: returnToVehicleSessionList
                        )
                    }
                }
            }
            .accessibilityIdentifier("macos-connection-history")
        }
        .onAppear { send(.refreshRequested) }
        .onChange(of: Set(state.sessions.map(\.id))) { _, availableSessionIDs in
            navigationState.returnFromDeletedSession(availableSessionIDs: availableSessionIDs)
        }
        .alert(
            "history.delete.warning.title",
            isPresented: Binding(
                get: { state.sessionDeletionPrompt != nil },
                set: { if !$0 { send(.sessionDeletionCancelled) } }
            ),
            presenting: state.sessionDeletionPrompt
        ) { _ in
            Button("history.delete.cancel", role: .cancel) {
                send(.sessionDeletionCancelled)
            }
            Button("history.delete.confirm", role: .destructive) {
                send(.sessionDeletionConfirmed)
            }
        } message: { prompt in
            Text(sessionDeletionMessage(prompt))
        }
        .alert(
            "history.delete.error.title",
            isPresented: Binding(
                get: { state.sessionDeletionFailureKey != nil },
                set: { if !$0 { send(.sessionDeletionFailureDismissed) } }
            )
        ) {
            Button("history.delete.error.dismiss") {
                send(.sessionDeletionFailureDismissed)
            }
        } message: {
            Text("history.delete.error")
        }
        .alert(
            "history.stop_review.title",
            isPresented: Binding(
                get: { state.stopReviewPrompt != nil },
                set: { if !$0 { send(.stopReviewCancelled) } }
            ),
            presenting: state.stopReviewPrompt
        ) { _ in
            Button("history.stop_review.cancel", role: .cancel) { send(.stopReviewCancelled) }
            Button("history.stop_review.confirm") { send(.stopReviewConfirmed) }
        } message: { prompt in
            Text(stopReviewMessageKey(prompt.observedReason))
        }
        .alert(
            "history.stop_review.error.title",
            isPresented: Binding(
                get: { state.stopReviewFailureKey != nil },
                set: { if !$0 { send(.stopReviewFailureDismissed) } }
            )
        ) {
            Button("history.stop_review.error.dismiss") { send(.stopReviewFailureDismissed) }
        } message: {
            Text("history.stop_review.error")
        }
    }

    /// 観測済み終了理由に対応する停止確認本文を返します。
    ///
    /// 責務: 1件の確認可能な終了理由を断定を避けたユーザー確認文へ変換します。
    /// - Parameter reason: アプリが観測した終了理由。
    /// - Returns: 終了理由に対応するローカライズキー。
    private func stopReviewMessageKey(_ reason: ConnectionSessionEndReason) -> LocalizedStringKey {
        reason == .vehicleNoResponse
            ? "history.stop_review.message.no_response"
            : "history.stop_review.message.connection_lost"
    }

    /// 履歴画面へ抑制された奥行きを与える背景です。
    private var historyBackground: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            RadialGradient(colors: [Color.accentColor.opacity(0.075), .clear], center: .topTrailing, startRadius: 0, endRadius: 620 * metrics.scale)
        }
    }

    /// 履歴総数と記録済み総走行時間を示す画面上部カードです。
    private var hero: some View {
        HStack(spacing: 20 * metrics.scale) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 31 * metrics.scale, weight: .semibold)).foregroundStyle(.tint)
                .frame(width: 76 * metrics.scale, height: 76 * metrics.scale)
                .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 22 * metrics.scale, style: .continuous))
            VStack(alignment: .leading, spacing: 5 * metrics.scale) {
                Text("history.eyebrow").font(.system(size: 10 * metrics.scale, weight: .bold, design: .rounded)).tracking(1.8 * metrics.scale).foregroundStyle(.tint)
                Text("history.title").font(.system(size: 30 * metrics.scale, weight: .bold, design: .rounded))
                Text("history.subtitle").font(.system(size: 13 * metrics.scale, weight: .medium)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12 * metrics.scale)
            summary(value: "\(state.sessions.count)", titleKey: "history.summary.total", color: .primary)
            summary(value: durationText(state.totalRecordedDuration), titleKey: "history.summary.duration", color: .cyan)
        }
        .padding(24 * metrics.scale)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26 * metrics.scale, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 26 * metrics.scale, style: .continuous).stroke(Color.primary.opacity(0.08)) }
    }

    /// 進行中セッションを終了済みアーカイブから分離して表示します。
    @ViewBuilder private var activeSection: some View {
        if !state.activeSessions.isEmpty {
            sectionTitle("history.active.title", systemImage: "dot.radiowaves.left.and.right")
            ForEach(state.activeSessions) { session in activeSessionCard(session) }
        }
    }

    /// 終了済みセッションを車両単位のグリッドとして表示します。
    private var archiveSection: some View {
        VStack(alignment: .leading, spacing: 13 * metrics.scale) {
            sectionTitle("history.archive.title", systemImage: "car.2.fill")
            if state.vehicleGroups.isEmpty {
                Text("history.archive.empty").foregroundStyle(.secondary).padding(24 * metrics.scale).frame(maxWidth: .infinity)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 20 * metrics.scale, style: .continuous))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300 * metrics.scale), spacing: 14 * metrics.scale)], spacing: 14 * metrics.scale) {
                    ForEach(state.vehicleGroups) { group in
                        NavigationLink(value: MacOSConnectionHistoryRoute.vehicleSessions(group.id)) { vehicleGroupCard(group) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("macos-history-vehicle-\(groupIdentifier(group.id))")
                    }
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
        HStack(spacing: 18 * metrics.scale) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 24 * metrics.scale, weight: .semibold)).foregroundStyle(.green)
                .frame(width: 58 * metrics.scale, height: 58 * metrics.scale)
                .background(.green.opacity(0.13), in: RoundedRectangle(cornerRadius: 18 * metrics.scale, style: .continuous))
            VStack(alignment: .leading, spacing: 4 * metrics.scale) {
                Text(vehicleName(session)).font(.system(size: 17 * metrics.scale, weight: .bold, design: .rounded))
                Text("history.active.recording").font(.system(size: 10.5 * metrics.scale, weight: .bold)).foregroundStyle(.green)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4 * metrics.scale) {
                Text("history.active.elapsed").font(.system(size: 9 * metrics.scale, weight: .semibold)).foregroundStyle(.tertiary)
                Text(session.startedAt, style: .timer).font(.system(size: 25 * metrics.scale, weight: .bold, design: .monospaced)).foregroundStyle(.green)
            }
            Divider().frame(height: 42 * metrics.scale)
            VStack(alignment: .trailing, spacing: 4 * metrics.scale) {
                Text("history.started").font(.system(size: 9 * metrics.scale, weight: .semibold)).foregroundStyle(.tertiary)
                Text(session.startedAt, format: .dateTime.year().month().day().hour().minute())
                    .font(.system(size: 11 * metrics.scale, weight: .semibold, design: .monospaced))
            }
        }
        .padding(20 * metrics.scale)
        .background(LinearGradient(colors: [.green.opacity(0.115), Color.primary.opacity(0.03)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 22 * metrics.scale, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 22 * metrics.scale, style: .continuous).stroke(.green.opacity(0.28)) }
        .shadow(color: .green.opacity(0.09), radius: 16 * metrics.scale, y: 7 * metrics.scale)
    }

    /// 1台分の終了済み履歴集計を遷移可能なカードとして描画します。
    ///
    /// 責務: 1件の車両別履歴集計を件数、総時間、総走行距離と警告状態を持つカードへ変換します。
    /// - Parameter group: 表示する車両別履歴集計。
    /// - Returns: 車両情報、セッション件数、総時間、総走行距離、中断警告を含むカード。
    private func vehicleGroupCard(_ group: ConnectionHistoryVehicleGroup) -> some View {
        VStack(alignment: .leading, spacing: 16 * metrics.scale) {
            HStack(spacing: 12 * metrics.scale) {
                Image(systemName: "car.side.fill").font(.system(size: 20 * metrics.scale, weight: .semibold))
                    .foregroundStyle(group.interruptedCount > 0 ? Color.orange : Color.accentColor)
                    .frame(width: 48 * metrics.scale, height: 48 * metrics.scale)
                    .background((group.interruptedCount > 0 ? Color.orange : Color.accentColor).opacity(0.12), in: RoundedRectangle(cornerRadius: 14 * metrics.scale, style: .continuous))
                VStack(alignment: .leading, spacing: 4 * metrics.scale) {
                    Text(group.vehicle?.name.nonEmpty ?? String(localized: "history.vehicle.unassigned"))
                        .font(.system(size: 16 * metrics.scale, weight: .bold, design: .rounded)).lineLimit(1)
                    if let identifier = group.vehicle?.displayIdentifier, !identifier.isEmpty {
                        Text(identifier).font(.system(size: 9.5 * metrics.scale, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                Image(systemName: "arrow.up.right").font(.system(size: 10 * metrics.scale, weight: .bold)).foregroundStyle(.tertiary)
            }
            Divider().opacity(0.55)
            HStack {
                metric("\(group.sessionCount)", key: "history.vehicle.sessions")
                metric(durationText(group.totalDuration), key: "history.summary.duration")
                metric(distanceText(group.totalDistanceKilometers), key: "history.summary.distance")
                Spacer()
                if group.interruptedCount > 0 { warningBadge(group.interruptedCount) }
            }
        }
        .padding(18 * metrics.scale).frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20 * metrics.scale, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 20 * metrics.scale, style: .continuous).stroke(group.interruptedCount > 0 ? .orange.opacity(0.25) : Color.primary.opacity(0.07)) }
    }

    /// 選択車両の絞り込み可能な終了済みセッション一覧を描画します。
    ///
    /// 責務: 1台分の履歴へ複合絞り込みと並び替えを適用したデスクトップ一覧を描画します。
    /// - Parameter id: 表示する車両グループ識別子。
    /// - Returns: 絞り込み操作とセッション詳細導線を含む画面。
    private func vehicleSessionList(for id: ConnectionHistoryVehicleGroupID) -> some View {
        let group = state.vehicleGroups.first(where: { $0.id == id })
        let sessions = state.filteredSessions(for: id)
        return ScrollView {
            VStack(alignment: .leading, spacing: 18 * metrics.scale) {
                vehicleDetailHeader(group)
                filterPanel
                if sessions.isEmpty { noFilterResults } else {
                    LazyVStack(spacing: 10 * metrics.scale) {
                        ForEach(sessions) { session in
                            NavigationLink(value: MacOSConnectionHistoryRoute.sessionDetail(session.id)) { sessionRow(session) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("macos-history-session-\(session.id.rawValue.uuidString)")
                        }
                    }
                }
            }
            .padding(28 * metrics.scale)
        }
        .background(historyBackground)
        .navigationBarBackButtonHidden(true)
    }

    /// 車両別履歴の文脈と戻る操作を一体化した詳細ヘッダーを描画します。
    ///
    /// 責務: 1件の車両グループを戻る操作、車両情報、履歴集計を含む詳細ヘッダーへ変換します。
    /// - Parameter group: 表示する車両別履歴集計。見つからない場合は未関連付け表示を使用します。
    /// - Returns: 車両別履歴画面の先頭に配置するコンテキストカード。
    private func vehicleDetailHeader(_ group: ConnectionHistoryVehicleGroup?) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 18 * metrics.scale) {
                vehicleBackButton
                vehicleDetailIdentity(group)
                Spacer(minLength: 16 * metrics.scale)
                vehicleDetailMetrics(group)
            }

            VStack(alignment: .leading, spacing: 14 * metrics.scale) {
                HStack(spacing: 14 * metrics.scale) {
                    vehicleBackButton
                    vehicleDetailIdentity(group)
                    Spacer(minLength: 0)
                }
                Divider().opacity(0.55)
                vehicleDetailMetrics(group)
            }
        }
        .padding(20 * metrics.scale)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22 * metrics.scale, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22 * metrics.scale, style: .continuous)
                .stroke(Color.primary.opacity(0.08))
        }
    }

    /// 車両別履歴ヘッダー内でアーカイブへ戻る操作です。
    private var vehicleBackButton: some View {
        Button {
            returnToVehicleArchive()
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
        .accessibilityLabel(Text("history.navigation.back"))
        .accessibilityIdentifier("macos-history-vehicle-back")
        .help(Text("history.navigation.back"))
    }

    /// 接続履歴内の画面遷移経路を車両別アーカイブまで戻します。
    ///
    /// 責務: 現在の接続履歴内ナビゲーション経路をルートへ戻します。
    private func returnToVehicleArchive() {
        navigationState.returnToVehicleArchive()
    }

    /// 接続履歴内の画面遷移経路を車両セッション一覧へ1段戻します。
    ///
    /// 責務: 現在のセッション詳細遷移だけを経路から取り除きます。
    private func returnToVehicleSessionList() {
        navigationState.returnToVehicleSessionList()
    }

    /// 全端末削除警告の件数と容量を含む本文を返します。
    ///
    /// 責務: 1件のセッション削除確認状態を不可逆性と実Raw集計を含む警告文へ変換します。
    /// - Parameter prompt: Applicationが準備した全端末削除確認内容。
    /// - Returns: Raw件数と容量を含むユーザー向け警告本文。
    private func sessionDeletionMessage(_ prompt: ConnectionSessionDeletionPrompt) -> String {
        let format = String(localized: "history.delete.warning.message")
        let bytes = ByteCountFormatter.string(fromByteCount: max(0, prompt.byteCount), countStyle: .file)
        return String(format: format, locale: .autoupdatingCurrent, prompt.recordCount, bytes)
    }

    /// 車両別履歴ヘッダーの車両識別表示を描画します。
    ///
    /// 責務: 1件の車両グループをシンボル、名称、表示識別子を含む識別表示へ変換します。
    /// - Parameter group: 表示する車両別履歴集計。見つからない場合は未関連付け表示を使用します。
    /// - Returns: 車両別履歴ヘッダー用の車両識別表示。
    private func vehicleDetailIdentity(_ group: ConnectionHistoryVehicleGroup?) -> some View {
        HStack(spacing: 14 * metrics.scale) {
            Image(systemName: "car.side.fill")
                .font(.system(size: 24 * metrics.scale, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 58 * metrics.scale, height: 58 * metrics.scale)
                .background(Color.accentColor.opacity(0.13), in: RoundedRectangle(cornerRadius: 18 * metrics.scale, style: .continuous))

            VStack(alignment: .leading, spacing: 4 * metrics.scale) {
                Text("history.archive.title")
                    .font(.system(size: 9.5 * metrics.scale, weight: .bold, design: .rounded))
                    .tracking(1.1 * metrics.scale)
                    .foregroundStyle(.tint)
                Text(group?.vehicle?.name.nonEmpty ?? String(localized: "history.vehicle.unassigned"))
                    .font(.system(size: 26 * metrics.scale, weight: .bold, design: .rounded))
                    .lineLimit(1)
                if let identifier = group?.vehicle?.displayIdentifier, !identifier.isEmpty {
                    Text(identifier)
                        .font(.system(size: 10 * metrics.scale, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    /// 車両別履歴ヘッダーの集計表示を描画します。
    ///
    /// 責務: 1件の車両グループをセッション数、総時間、総走行距離、中断件数の集計表示へ変換します。
    /// - Parameter group: 表示する車両別履歴集計。見つからない場合はゼロ値を使用します。
    /// - Returns: 車両別履歴ヘッダー用の集計表示。
    private func vehicleDetailMetrics(_ group: ConnectionHistoryVehicleGroup?) -> some View {
        HStack(spacing: 18 * metrics.scale) {
            metric("\(group?.sessionCount ?? 0)", key: "history.vehicle.sessions")
            metric(durationText(group?.totalDuration ?? 0), key: "history.summary.duration")
            metric(distanceText(group?.totalDistanceKilometers), key: "history.summary.distance")
            if let count = group?.interruptedCount, count > 0 { warningBadge(count) }
        }
    }

    /// 日付範囲、終了理由、並び順を同時指定できる操作パネルです。
    private var filterPanel: some View {
        VStack(alignment: .leading, spacing: 13 * metrics.scale) {
            HStack {
                Label("history.filter.title", systemImage: "line.3.horizontal.decrease.circle.fill")
                    .font(.system(size: 14 * metrics.scale, weight: .bold, design: .rounded))
                Spacer()
                if state.hasActiveFilters { Button("history.filter.reset") { send(.filtersReset) }.buttonStyle(.borderless) }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14 * metrics.scale) { filterControls }
                VStack(alignment: .leading, spacing: 10 * metrics.scale) { filterControls }
            }
        }
        .padding(17 * metrics.scale)
        .background(Color.accentColor.opacity(0.065), in: RoundedRectangle(cornerRadius: 18 * metrics.scale, style: .continuous))
    }

    /// 複合絞り込みパネルに並べる個別操作です。
    @ViewBuilder private var filterControls: some View {
        optionalDateControl(title: "history.filter.from", date: state.filterStartDate, fallback: state.closedSessions.map(\.startedAt).min() ?? .distantPast) { send(.filterStartDateChanged($0)) }
        optionalDateControl(title: "history.filter.to", date: state.filterEndDate, fallback: state.closedSessions.map(\.startedAt).max() ?? .distantPast) { send(.filterEndDateChanged($0)) }
        Picker("history.filter.reason", selection: Binding(get: { state.endReasonFilter }, set: { send(.endReasonFilterChanged($0)) })) {
            ForEach(ConnectionHistoryEndReasonFilter.allCases, id: \.self) { Text(endReasonFilterKey($0)).tag($0) }
        }.frame(minWidth: 150 * metrics.scale)
        Picker("history.sort.title", selection: Binding(get: { state.sortOrder }, set: { send(.sortOrderChanged($0)) })) {
            ForEach(ConnectionHistorySortOrder.allCases, id: \.self) { Text(sortOrderKey($0)).tag($0) }
        }.frame(minWidth: 150 * metrics.scale)
    }

    /// 任意の日付条件を有効化できる操作として描画します。
    ///
    /// 責務: 1件の任意日付を有効化操作と日付選択操作へ変換します。
    /// - Parameters:
    ///   - title: 日付条件のローカライズキー。
    ///   - date: 現在選択中の日付。
    ///   - fallback: 有効化時に使う履歴由来の初期日。
    ///   - update: 変更後の日付通知先。
    /// - Returns: 有効化チェックと日付選択欄を含む操作。
    private func optionalDateControl(title: LocalizedStringKey, date: Date?, fallback: Date, update: @escaping (Date?) -> Void) -> some View {
        HStack(spacing: 7 * metrics.scale) {
            Toggle(title, isOn: Binding(get: { date != nil }, set: { update($0 ? fallback : nil) })).toggleStyle(.checkbox)
            if let date { DatePicker("", selection: Binding(get: { date }, set: { update($0) }), displayedComponents: .date).labelsHidden() }
        }
    }

    /// 1件の終了済みセッションを詳細遷移行として描画します。
    ///
    /// 責務: 1件の終了済みセッションを日時、時間、走行距離、終了理由を持つ一覧行へ変換します。
    /// - Parameter session: 表示する終了済みセッション。
    /// - Returns: 詳細画面へ遷移可能なセッション行。
    private func sessionRow(_ session: ConnectionSession) -> some View {
        HStack(spacing: 14 * metrics.scale) {
            if session.status == .completed {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
                    .font(.system(size: 18 * metrics.scale))
            } else {
                WarningTriangleIcon(size: 18 * metrics.scale)
            }
            Text(session.startedAt, format: .dateTime.year().month().day().hour().minute())
                .font(.system(size: 12 * metrics.scale, weight: .semibold, design: .monospaced)).frame(minWidth: 170 * metrics.scale, alignment: .leading)
            Text(endReasonKey(session.endReason)).font(.system(size: 11 * metrics.scale, weight: .semibold)).foregroundStyle(session.status == .completed ? Color.secondary : Color.orange)
            Spacer()
            VStack(alignment: .trailing, spacing: 3 * metrics.scale) {
                Label(durationText(sessionDuration(session)), systemImage: "clock")
                Label(distanceText(session.recordedDistanceKilometers), systemImage: "road.lanes")
            }
            .font(.system(size: 10 * metrics.scale, weight: .semibold, design: .monospaced))
            .foregroundStyle(.secondary)
            Text(shortID(session.id)).font(.system(size: 9 * metrics.scale, design: .monospaced)).foregroundStyle(.tertiary)
            Image(systemName: "chevron.right").font(.system(size: 9 * metrics.scale, weight: .bold)).foregroundStyle(.tertiary)
        }
        .padding(15 * metrics.scale)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 15 * metrics.scale, style: .continuous))
    }

    /// 絞り込み結果が空であることを表示します。
    private var noFilterResults: some View {
        ContentUnavailableView("history.filter.empty", systemImage: "magnifyingglass", description: Text("history.filter.empty.body"))
            .frame(maxWidth: .infinity).padding(.vertical, 40 * metrics.scale)
    }

    /// 履歴が存在しないことを表示します。
    private var emptyState: some View {
        ContentUnavailableView("history.empty.title", systemImage: "road.lanes", description: Text("history.empty.body"))
            .padding(38 * metrics.scale).frame(maxWidth: .infinity)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 24 * metrics.scale, style: .continuous))
    }

    /// 履歴保存先を利用できない状態と再試行操作を示します。
    private var failureState: some View {
        VStack(spacing: 14 * metrics.scale) {
            Image(systemName: "externaldrive.badge.exclamationmark").font(.system(size: 34 * metrics.scale)).foregroundStyle(.orange)
            Text("history.error.storage").font(.system(size: 15 * metrics.scale, weight: .semibold))
            Button("history.error.retry") { send(.refreshRequested) }.buttonStyle(.borderedProminent)
        }.padding(34 * metrics.scale).frame(maxWidth: .infinity)
            .background(Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 24 * metrics.scale, style: .continuous))
    }

    /// セクションのローカライズ見出しを生成します。
    ///
    /// 責務: 1件の見出しキーとシンボルを履歴セクション見出しへ変換します。
    /// - Parameters:
    ///   - title: 見出しのローカライズキー。
    ///   - systemImage: 見出しを補助するSF Symbol名。
    /// - Returns: 履歴セクション用見出し。
    private func sectionTitle(_ title: LocalizedStringKey, systemImage: String) -> some View {
        Label(title, systemImage: systemImage).font(.system(size: 18 * metrics.scale, weight: .bold, design: .rounded)).padding(.horizontal, 2 * metrics.scale)
    }

    /// 文字列集計値を大きな数字と見出しで描画します。
    ///
    /// 責務: 1件の集計値をmacOS用の要約表示へ変換します。
    /// - Parameters:
    ///   - value: 表示値。
    ///   - titleKey: 値の意味を示すキー。
    ///   - color: 値の表示色。
    /// - Returns: 値と見出しを含む要約。
    private func summary(value: String, titleKey: LocalizedStringKey, color: Color) -> some View {
        VStack(alignment: .trailing, spacing: 2 * metrics.scale) { Text(value).font(.system(size: 24 * metrics.scale, weight: .bold, design: .rounded).monospacedDigit()).foregroundStyle(color); Text(titleKey).font(.system(size: 9.5 * metrics.scale, weight: .semibold)).foregroundStyle(.secondary) }.frame(minWidth: 78 * metrics.scale)
    }

    /// 車両カード用の短い集計列を生成します。
    ///
    /// 責務: 1件の文字列集計値を車両カード用ラベルへ変換します。
    /// - Parameters:
    ///   - value: 表示値。
    ///   - key: 値の意味を示すキー。
    /// - Returns: 値と見出しを含む集計列。
    private func metric(_ value: String, key: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2 * metrics.scale) { Text(value).font(.system(size: 13 * metrics.scale, weight: .bold, design: .rounded).monospacedDigit()); Text(key).font(.system(size: 8.5 * metrics.scale, weight: .semibold)).foregroundStyle(.tertiary) }.frame(minWidth: 74 * metrics.scale, alignment: .leading)
    }

    /// 中断件数を注意バッジとして描画します。
    ///
    /// 責務: 1件の中断件数を色とシンボルを併用した警告へ変換します。
    /// - Parameter count: 表示する中断件数。
    /// - Returns: 中断を示す警告バッジ。
    private func warningBadge(_ count: Int) -> some View {
        HStack(spacing: 4 * metrics.scale) {
            WarningTriangleIcon(size: 10 * metrics.scale)
            Text("\(count)")
        }
            .font(.system(size: 10 * metrics.scale, weight: .bold)).foregroundStyle(.orange)
            .padding(.horizontal, 9 * metrics.scale).padding(.vertical, 6 * metrics.scale).background(.orange.opacity(0.11), in: Capsule())
            .accessibilityLabel(Text("history.warning.interrupted"))
            .accessibilityValue(Text(count, format: .number))
    }

    /// 車両名称を未確定状態も含めて返します。
    ///
    /// 責務: 1件のセッションを表示可能な車両名称へ変換します。
    /// - Parameter session: 車両名称を求めるセッション。
    /// - Returns: 登録車両名または識別中の文言。
    private func vehicleName(_ session: ConnectionSession) -> String { session.vehicle?.name.nonEmpty ?? String(localized: "history.vehicle.pending") }

    /// セッションの確定走行時間を返します。
    ///
    /// 責務: 1件の終了済みセッションから非負の記録時間を算出します。
    /// - Parameter session: 時間を求める終了済みセッション。
    /// - Returns: 秒単位の非負記録時間。
    private func sessionDuration(_ session: ConnectionSession) -> TimeInterval { max(0, session.endedAt?.timeIntervalSince(session.startedAt) ?? 0) }

    /// 秒数を単位名が明確な時分表記へ変換します。
    ///
    /// 責務: 1件の秒数を履歴画面用の固定幅時間文字列へ変換します。
    /// - Parameter interval: 表示する秒数。
    /// - Returns: 現在ロケールで時間と分を明記した文字列。
    private func durationText(_ interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = interval >= 3_600 ? [.hour, .minute] : [.minute]
        formatter.unitsStyle = .short
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: max(0, interval)) ?? String(localized: "history.duration.zero")
    }

    /// セッション差分をメートルまたはキロメートルの明確な距離表記へ変換します。
    ///
    /// 責務: 1件の任意走行距離を距離単位付き表示または非対応表示へ変換します。
    /// - Parameter kilometers: A6累積値の差分。確定できない場合は `nil`。
    /// - Returns: 1 km未満はm、1 km以上はkm、未確定時は走行距離非対応の文字列。
    private func distanceText(_ kilometers: Double?) -> String {
        guard let kilometers else { return String(localized: "history.distance.unsupported") }
        if kilometers < 1 { return String.localizedStringWithFormat("%.0f m", kilometers * 1_000) }
        return String.localizedStringWithFormat("%.1f km", kilometers)
    }

    /// セッションIDを短縮表示へ変換します。
    ///
    /// 責務: 1件のセッションIDを先頭8文字の大文字表記へ変換します。
    /// - Parameter id: 短縮するセッションID。
    /// - Returns: 短縮UUID表記。
    private func shortID(_ id: ConnectionSessionID) -> String { String(id.rawValue.uuidString.prefix(8)).uppercased() }

    /// 車両グループ識別子をアクセシビリティ識別用文字列へ変換します。
    ///
    /// 責務: 1件の車両グループ識別子を安定したUI識別文字列へ変換します。
    /// - Parameter id: 変換する車両グループ識別子。
    /// - Returns: 登録車両UUIDまたは未関連付け識別子。
    private func groupIdentifier(_ id: ConnectionHistoryVehicleGroupID) -> String { switch id { case let .registered(vehicleID): vehicleID.rawValue.uuidString; case .unassigned: "unassigned" } }

    /// 終了理由条件の表示キーを返します。
    ///
    /// 責務: 1件の終了理由条件をPicker用ローカライズキーへ変換します。
    /// - Parameter filter: 表示する終了理由条件。
    /// - Returns: 条件名のローカライズキー。
    private func endReasonFilterKey(_ filter: ConnectionHistoryEndReasonFilter) -> LocalizedStringKey {
        LocalizedStringKey("history.reason." + filter.rawValue)
    }

    /// 並び順の表示キーを返します。
    ///
    /// 責務: 1件の並び順をPicker用ローカライズキーへ変換します。
    /// - Parameter order: 表示する並び順。
    /// - Returns: 並び順名のローカライズキー。
    private func sortOrderKey(_ order: ConnectionHistorySortOrder) -> LocalizedStringKey {
        LocalizedStringKey("history.sort." + order.rawValue)
    }

    /// 終了理由の表示キーを返します。
    ///
    /// 責務: 1件の終了理由をセッション行用ローカライズキーへ変換します。
    /// - Parameter reason: 表示する終了理由。
    /// - Returns: 終了理由名のローカライズキー。
    private func endReasonKey(_ reason: ConnectionSessionEndReason?) -> LocalizedStringKey {
        LocalizedStringKey("history.reason." + (reason?.rawValue ?? "all"))
    }
}

private extension String {
    /// 空文字列を未設定として扱った表示可能文字列です。
    var nonEmpty: String? { isEmpty ? nil : self }
}
#endif
