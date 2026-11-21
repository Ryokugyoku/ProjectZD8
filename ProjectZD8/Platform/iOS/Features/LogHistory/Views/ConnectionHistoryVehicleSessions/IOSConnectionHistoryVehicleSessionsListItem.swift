#if os(iOS)
import SwiftUI

/// 1件のセッション行へ詳細導線、必要なアップロード、端末容量解放操作を縦に並べた一覧項目です。
struct IOSConnectionHistoryVehicleSessionsListItem: View {
    /// 表示する終了済みセッションです。
    let session: ConnectionSession
    /// 手動アップロード操作を表示するかです。
    let canUpload: Bool
    /// 端末容量解放ボタンを表示するかです。
    let canReleaseRawCache: Bool
    /// 送信中のセッションIDです。どれも送信中でなければ `nil`。
    let uploadingSessionID: ConnectionSessionID?
    /// 送信中アップロードの進捗(0〜1)です。
    let uploadProgress: Double?
    /// 項目の操作をApplicationへ通知します。
    let send: (ConnectionHistoryAction) -> Void

    /// 詳細導線と、表示条件を満たす操作を区切り線付きで並べます。
    ///
    /// 責務: 1件の終了済みセッションを詳細遷移と現在の保管状態に必要な操作へ配置します。
    var body: some View {
        VStack(spacing: 0) {
            NavigationLink(value: session.id) { IOSConnectionHistoryVehicleSessionsRow(session: session) }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ios-history-session-\(session.id.rawValue.uuidString)")
            if canUpload {
                Divider().padding(.horizontal, 15)
                IOSConnectionHistoryVehicleSessionsUploadAction(
                    session: session,
                    uploadingSessionID: uploadingSessionID,
                    uploadProgress: uploadProgress,
                    send: send
                )
            }
            if canReleaseRawCache {
                Divider().padding(.horizontal, 15)
                releaseRawButton
            }
        }
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// 端末のRawを削除して容量を解放する操作です。
    private var releaseRawButton: some View {
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
#endif
