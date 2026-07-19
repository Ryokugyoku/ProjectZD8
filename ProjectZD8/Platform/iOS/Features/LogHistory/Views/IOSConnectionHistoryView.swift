#if os(iOS)
import SwiftUI

/// iPhone向けに接続中と過去セッションを時系列カードで描画します。
struct IOSConnectionHistoryView: View {
    /// LogHistoryが提供する現在の履歴状態です。
    let state: ConnectionHistoryState
    /// 履歴の型付き操作をApplicationへ通知します。
    let send: (ConnectionHistoryAction) -> Void

    /// iPhone向けの接続履歴と詳細導線を提供します。
    ///
    /// 責務: 接続セッション状態をモバイル向けの履歴一覧として描画します。
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    hero

                    if state.phase == .failed {
                        failureState
                    } else if state.sessions.isEmpty {
                        emptyState
                    } else {
                        ForEach(state.sessions) { session in
                            NavigationLink(value: session.id) {
                                sessionCard(session)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("ios-history-session-\(session.id.rawValue.uuidString)")
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .navigationDestination(for: ConnectionSessionID.self) { id in
                if let session = state.sessions.first(where: { $0.id == id }) {
                    IOSDrivingLogDevelopmentView(session: session)
                }
            }
            .refreshable { send(.refreshRequested) }
            .accessibilityIdentifier("ios-connection-history")
        }
    }

    /// 履歴件数と現在接続数を示す画面上部カードです。
    private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.accentColor.opacity(0.16))
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.tint)
                }
                .frame(width: 58, height: 58)

                VStack(alignment: .leading, spacing: 5) {
                    Text("history.eyebrow")
                        .font(.caption.weight(.bold))
                        .tracking(1.5)
                        .foregroundStyle(.tint)
                    Text("history.title")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    Text("history.subtitle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                summaryPill(value: state.sessions.count, titleKey: "history.summary.total", color: .primary)
                summaryPill(value: state.connectedCount, titleKey: "history.summary.connected", color: .green)
            }
        }
        .padding(22)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    /// 履歴が存在しないことを落ち着いたカードで示します。
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "road.lanes")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.secondary)
            Text("history.empty.title")
                .font(.system(.title3, design: .rounded, weight: .bold))
            Text("history.empty.body")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(30)
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    /// 履歴保存先を利用できない状態と再試行操作を示します。
    private var failureState: some View {
        VStack(spacing: 14) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(.orange)
            Text("history.error.storage")
                .font(.headline)
                .multilineTextAlignment(.center)
            Button("history.error.retry") { send(.refreshRequested) }
                .buttonStyle(.borderedProminent)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    /// 1件の接続セッションを車両、状態、時刻、IDのカードとして描画します。
    ///
    /// 責務: 1件の接続セッションを詳細遷移可能なモバイルカードへ変換します。
    /// - Parameter session: 描画する接続セッション。
    /// - Returns: 車両とセッション情報をまとめたカード。
    private func sessionCard(_ session: ConnectionSession) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(statusColor(session.status).opacity(0.14))
                    Image(systemName: statusIcon(session.status))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(statusColor(session.status))
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text(vehicleName(session))
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .lineLimit(1)
                    if let identifier = session.vehicle?.displayIdentifier, !identifier.isEmpty {
                        Text(identifier)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)
                statusBadge(session.status)
            }

            HStack(spacing: 0) {
                timeColumn(titleKey: "history.started", date: session.startedAt)
                Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 1, height: 40).padding(.horizontal, 14)
                if let endedAt = session.endedAt {
                    timeColumn(titleKey: "history.ended", date: endedAt)
                } else {
                    timeColumn(titleKey: "history.ended", value: String(localized: "history.in.progress"))
                }
            }

            HStack {
                Text("history.session.id")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                Text(shortID(session.id))
                    .font(.caption2.monospaced().weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(statusColor(session.status).opacity(session.status == .connected ? 0.30 : 0.08), lineWidth: 1)
        }
        .shadow(color: session.status == .connected ? Color.green.opacity(0.10) : Color.clear, radius: 18, y: 8)
    }

    /// 件数と短い見出しを要約ピルとして描画します。
    ///
    /// 責務: 1件の整数集計値を画面上部のコンパクトな要約へ変換します。
    /// - Parameters:
    ///   - value: 表示する件数。
    ///   - titleKey: 件数の意味を示すローカライズキー。
    ///   - color: 値とシンボルへ適用する色。
    /// - Returns: 件数と見出しを含む要約ピル。
    private func summaryPill(value: Int, titleKey: LocalizedStringKey, color: Color) -> some View {
        HStack(spacing: 8) {
            Text(value, format: .number).font(.headline.monospacedDigit()).foregroundStyle(color)
            Text(titleKey).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(Color.primary.opacity(0.055), in: Capsule())
    }

    /// 状態をローカライズ済みバッジとして描画します。
    ///
    /// 責務: 1件のセッション状態を色とテキストを併用したバッジへ変換します。
    /// - Parameter status: 表示するセッション状態。
    /// - Returns: 状態を示すアクセシブルなバッジ。
    private func statusBadge(_ status: ConnectionSession.Status) -> some View {
        HStack(spacing: 5) {
            Circle().fill(statusColor(status)).frame(width: 6, height: 6)
            Text(statusKey(status)).font(.caption2.weight(.bold))
        }
        .foregroundStyle(statusColor(status))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(statusColor(status).opacity(0.11), in: Capsule())
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

    /// 日時を見出し付きの時刻列として描画します。
    ///
    /// 責務: 1件の日時を履歴カード用の短い時刻表示へ変換します。
    /// - Parameters:
    ///   - titleKey: 日時の意味を示すローカライズキー。
    ///   - date: 表示する日時。
    /// - Returns: 見出しとローカライズ済み時刻を含む列。
    private func timeColumn(titleKey: LocalizedStringKey, date: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titleKey).font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
            Text(date, format: .dateTime.month().day().hour().minute())
                .font(.caption.monospacedDigit().weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 任意文字列を見出し付きの時刻列位置へ描画します。
    ///
    /// 責務: 1件の短い状態文字列を履歴カードの時刻列形式へ変換します。
    /// - Parameters:
    ///   - titleKey: 値の意味を示すローカライズキー。
    ///   - value: 表示する短い状態文字列。
    /// - Returns: 見出しと値を含む列。
    private func timeColumn(titleKey: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titleKey).font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
            Text(value).font(.caption.weight(.semibold)).foregroundStyle(.green)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// セッション状態に対応する表示色を返します。
    ///
    /// 責務: 1件のセッション状態を一貫したiOS表示色へ写像します。
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
    /// 責務: 1件のセッション状態を色に依存しないiOSシンボルへ写像します。
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
