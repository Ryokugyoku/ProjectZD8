#if os(macOS)
import SwiftUI

/// macOS向けに接続中と過去セッションをコックピット調の一覧で描画します。
struct MacOSConnectionHistoryView: View {
    /// LogHistoryが提供する現在の履歴状態です。
    let state: ConnectionHistoryState
    /// 履歴の型付き操作をApplicationへ通知します。
    let send: (ConnectionHistoryAction) -> Void
    /// 現在のウインドウサイズに対応する表示寸法です。
    let metrics: MacOSAppShellMetrics

    /// macOS向けの接続履歴と詳細導線を提供します。
    ///
    /// 責務: 接続セッション状態をデスクトップ向けの履歴一覧として描画します。
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20 * metrics.scale) {
                    hero

                    if state.phase == .failed {
                        failureState
                    } else if state.sessions.isEmpty {
                        emptyState
                    } else {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 290 * metrics.scale), spacing: 14 * metrics.scale)],
                            spacing: 14 * metrics.scale
                        ) {
                            ForEach(state.sessions) { session in
                                NavigationLink(value: session.id) {
                                    sessionCard(session)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("macos-history-session-\(session.id.rawValue.uuidString)")
                            }
                        }
                    }
                }
                .padding(26 * metrics.scale)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .navigationDestination(for: ConnectionSessionID.self) { id in
                if let session = state.sessions.first(where: { $0.id == id }) {
                    MacOSDrivingLogDevelopmentView(session: session, metrics: metrics)
                }
            }
            .accessibilityIdentifier("macos-connection-history")
        }
    }

    /// 履歴の目的と集計値を示す画面上部カードです。
    private var hero: some View {
        HStack(spacing: 22 * metrics.scale) {
            ZStack {
                RoundedRectangle(cornerRadius: 22 * metrics.scale, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.22), Color.accentColor.opacity(0.07)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 32 * metrics.scale, weight: .semibold))
                    .foregroundStyle(.tint)
            }
            .frame(width: 78 * metrics.scale, height: 78 * metrics.scale)

            VStack(alignment: .leading, spacing: 6 * metrics.scale) {
                Text("history.eyebrow")
                    .font(.system(size: 10 * metrics.scale, weight: .bold, design: .rounded))
                    .tracking(1.8 * metrics.scale)
                    .foregroundStyle(.tint)
                Text("history.title")
                    .font(.system(size: 30 * metrics.scale, weight: .bold, design: .rounded))
                Text("history.subtitle")
                    .font(.system(size: 13 * metrics.scale, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12 * metrics.scale)

            summary(value: state.sessions.count, titleKey: "history.summary.total", color: .primary)
            summary(value: state.connectedCount, titleKey: "history.summary.connected", color: .green)
        }
        .padding(24 * metrics.scale)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26 * metrics.scale, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26 * metrics.scale, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    /// 履歴が存在しないことを中央カードで示します。
    private var emptyState: some View {
        VStack(spacing: 13 * metrics.scale) {
            Image(systemName: "road.lanes")
                .font(.system(size: 38 * metrics.scale, weight: .medium))
                .foregroundStyle(.secondary)
            Text("history.empty.title")
                .font(.system(size: 20 * metrics.scale, weight: .bold, design: .rounded))
            Text("history.empty.body")
                .font(.system(size: 13 * metrics.scale))
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(38 * metrics.scale)
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 24 * metrics.scale, style: .continuous))
    }

    /// 履歴保存先を利用できない状態と再試行操作を示します。
    private var failureState: some View {
        VStack(spacing: 14 * metrics.scale) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 34 * metrics.scale, weight: .medium))
                .foregroundStyle(.orange)
            Text("history.error.storage")
                .font(.system(size: 15 * metrics.scale, weight: .semibold))
            Button("history.error.retry") { send(.refreshRequested) }
                .buttonStyle(.borderedProminent)
        }
        .padding(34 * metrics.scale)
        .frame(maxWidth: .infinity)
        .background(Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 24 * metrics.scale, style: .continuous))
    }

    /// 1件の接続セッションを車両、状態、時刻、IDのカードとして描画します。
    ///
    /// 責務: 1件の接続セッションを詳細遷移可能なmacOSカードへ変換します。
    /// - Parameter session: 描画する接続セッション。
    /// - Returns: 車両とセッション情報をまとめたカード。
    private func sessionCard(_ session: ConnectionSession) -> some View {
        VStack(alignment: .leading, spacing: 16 * metrics.scale) {
            HStack(spacing: 12 * metrics.scale) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13 * metrics.scale, style: .continuous)
                        .fill(statusColor(session.status).opacity(0.13))
                    Image(systemName: statusIcon(session.status))
                        .font(.system(size: 18 * metrics.scale, weight: .semibold))
                        .foregroundStyle(statusColor(session.status))
                }
                .frame(width: 46 * metrics.scale, height: 46 * metrics.scale)

                VStack(alignment: .leading, spacing: 3 * metrics.scale) {
                    Text(vehicleName(session))
                        .font(.system(size: 15 * metrics.scale, weight: .bold, design: .rounded))
                        .lineLimit(1)
                    if let identifier = session.vehicle?.displayIdentifier, !identifier.isEmpty {
                        Text(identifier)
                            .font(.system(size: 10 * metrics.scale, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4 * metrics.scale)
                statusBadge(session.status)
            }

            Divider().opacity(0.55)

            HStack {
                dateColumn(titleKey: "history.started", date: session.startedAt)
                Spacer()
                if let endedAt = session.endedAt {
                    dateColumn(titleKey: "history.ended", date: endedAt)
                } else {
                    valueColumn(titleKey: "history.ended", valueKey: "history.in.progress")
                }
            }

            HStack {
                Text("history.session.id")
                    .font(.system(size: 9.5 * metrics.scale, weight: .semibold))
                    .foregroundStyle(.tertiary)
                Text(shortID(session.id))
                    .font(.system(size: 10 * metrics.scale, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10 * metrics.scale, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(18 * metrics.scale)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20 * metrics.scale, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20 * metrics.scale, style: .continuous)
                .stroke(statusColor(session.status).opacity(session.status == .connected ? 0.30 : 0.08), lineWidth: 1)
        }
        .shadow(color: session.status == .connected ? Color.green.opacity(0.10) : Color.clear, radius: 16 * metrics.scale, y: 7 * metrics.scale)
    }

    /// 履歴集計値を大きな数字と短い見出しで描画します。
    ///
    /// 責務: 1件の整数集計値をmacOS用の要約表示へ変換します。
    /// - Parameters:
    ///   - value: 表示する件数。
    ///   - titleKey: 件数の意味を示すローカライズキー。
    ///   - color: 数値へ適用する色。
    /// - Returns: 数値と見出しを縦に配置した要約。
    private func summary(value: Int, titleKey: LocalizedStringKey, color: Color) -> some View {
        VStack(alignment: .trailing, spacing: 2 * metrics.scale) {
            Text(value, format: .number)
                .font(.system(size: 25 * metrics.scale, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(color)
            Text(titleKey)
                .font(.system(size: 9.5 * metrics.scale, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 64 * metrics.scale)
    }

    /// 状態をローカライズ済みバッジとして描画します。
    ///
    /// 責務: 1件のセッション状態を色とテキストを併用したmacOSバッジへ変換します。
    /// - Parameter status: 表示するセッション状態。
    /// - Returns: 状態を示すアクセシブルなバッジ。
    private func statusBadge(_ status: ConnectionSession.Status) -> some View {
        HStack(spacing: 5 * metrics.scale) {
            Circle().fill(statusColor(status)).frame(width: 6 * metrics.scale, height: 6 * metrics.scale)
            Text(statusKey(status))
                .font(.system(size: 9.5 * metrics.scale, weight: .bold))
        }
        .foregroundStyle(statusColor(status))
        .padding(.horizontal, 9 * metrics.scale)
        .padding(.vertical, 6 * metrics.scale)
        .background(statusColor(status).opacity(0.11), in: Capsule())
    }

    /// 日時を見出し付きのカード情報列として描画します。
    ///
    /// 責務: 1件の日時を履歴カード用の短いmacOS表示へ変換します。
    /// - Parameters:
    ///   - titleKey: 日時の意味を示すローカライズキー。
    ///   - date: 表示する日時。
    /// - Returns: 見出しと日時を含む列。
    private func dateColumn(titleKey: LocalizedStringKey, date: Date) -> some View {
        VStack(alignment: .leading, spacing: 4 * metrics.scale) {
            Text(titleKey).font(.system(size: 9 * metrics.scale, weight: .semibold)).foregroundStyle(.tertiary)
            Text(date, format: .dateTime.year().month().day().hour().minute())
                .font(.system(size: 11 * metrics.scale, weight: .semibold, design: .monospaced))
        }
    }

    /// ローカライズ値を見出し付きのカード情報列として描画します。
    ///
    /// 責務: 1件の状態文言を履歴カードの情報列形式へ変換します。
    /// - Parameters:
    ///   - titleKey: 値の意味を示すローカライズキー。
    ///   - valueKey: 表示する値のローカライズキー。
    /// - Returns: 見出しと値を含む列。
    private func valueColumn(titleKey: LocalizedStringKey, valueKey: LocalizedStringKey) -> some View {
        VStack(alignment: .trailing, spacing: 4 * metrics.scale) {
            Text(titleKey).font(.system(size: 9 * metrics.scale, weight: .semibold)).foregroundStyle(.tertiary)
            Text(valueKey).font(.system(size: 11 * metrics.scale, weight: .semibold)).foregroundStyle(.green)
        }
    }

    /// 車両情報が未確定の場合を含む表示名称を返します。
    ///
    /// 責務: 1件のセッションから履歴カードに表示できる車両名称を返します。
    /// - Parameter session: 車両名称を求める接続セッション。
    /// - Returns: 登録車両名または識別中を示す文言。
    private func vehicleName(_ session: ConnectionSession) -> String {
        guard let name = session.vehicle?.name, !name.isEmpty else {
            return String(localized: "history.vehicle.pending")
        }
        return name
    }

    /// セッション状態に対応する表示色を返します。
    ///
    /// 責務: 1件のセッション状態を一貫したmacOS表示色へ写像します。
    /// - Parameter status: 色を求めるセッション状態。
    /// - Returns: 接続中、正常終了、中断を区別する色。
    private func statusColor(_ status: ConnectionSession.Status) -> Color {
        switch status {
        case .connected: .green
        case .completed: .blue
        case .interrupted: .orange
        }
    }

    /// セッション状態に対応するSF Symbol名を返します。
    ///
    /// 責務: 1件のセッション状態を色に依存しないmacOSシンボルへ写像します。
    /// - Parameter status: シンボルを求めるセッション状態。
    /// - Returns: 状態を区別するSF Symbol名。
    private func statusIcon(_ status: ConnectionSession.Status) -> String {
        switch status {
        case .connected: "antenna.radiowaves.left.and.right"
        case .completed: "checkmark"
        case .interrupted: "exclamationmark"
        }
    }

    /// セッション状態に対応するローカライズキーを返します。
    ///
    /// 責務: 1件のセッション状態を履歴バッジ用ローカライズキーへ写像します。
    /// - Parameter status: 文言を求めるセッション状態。
    /// - Returns: 状態表示に使用するローカライズキー。
    private func statusKey(_ status: ConnectionSession.Status) -> LocalizedStringKey {
        switch status {
        case .connected: "history.status.connected"
        case .completed: "history.status.completed"
        case .interrupted: "history.status.interrupted"
        }
    }

    /// UUIDを一覧識別に十分な短縮表記へ変換します。
    ///
    /// 責務: 1件のセッションIDを先頭8文字の大文字表記へ変換します。
    /// - Parameter id: 短縮表示するセッションID。
    /// - Returns: 先頭8文字の大文字UUID表記。
    private func shortID(_ id: ConnectionSessionID) -> String {
        String(id.rawValue.uuidString.prefix(8)).uppercased()
    }
}
#endif
