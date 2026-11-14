#if os(macOS)
import SwiftUI

/// 1件のセッション行へ詳細導線、必要なアップロード、端末容量解放操作を並べた一覧項目です。
struct MacOSConnectionHistoryVehicleSessionsListItem: View {
    /// 表示する終了済みセッションです。
    let session: ConnectionSession
    /// 手動アップロードボタンを表示するかです。
    let canUpload: Bool
    /// 端末容量解放ボタンを表示するかです。
    let canReleaseRawCache: Bool
    /// アップロード中のセッションIDです。どれも送信中でなければ `nil`。
    let uploadingSessionID: ConnectionSessionID?
    /// 送信中アップロードの進捗(0〜1)です。
    let uploadProgress: Double?
    /// 画面サイズに対応する表示倍率です。
    let scale: CGFloat
    /// 行の操作をApplicationへ通知します。
    let send: (ConnectionHistoryAction) -> Void

    /// 詳細導線と、表示条件を満たす操作ボタンを横に並べます。
    ///
    /// 責務: 1件の終了済みセッションを詳細遷移と現在の保管状態に必要な操作へ配置します。
    var body: some View {
        HStack(spacing: 8 * scale) {
            NavigationLink(value: MacOSConnectionHistoryRoute.sessionDetail(session.id)) {
                MacOSConnectionHistoryVehicleSessionsRow(session: session, scale: scale)
            }
                .buttonStyle(.plain)
                .accessibilityIdentifier("macos-history-session-\(session.id.rawValue.uuidString)")
            if canUpload { uploadButton }
            if canReleaseRawCache {
                Button {
                    send(.localRawRemovalRequested(session.id))
                } label: {
                    Label("history.raw.remove.button", systemImage: "externaldrive.badge.minus")
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .accessibilityIdentifier("macos-history-release-raw-\(session.id.rawValue.uuidString)")
            }
        }
    }

    /// 手動iCloudアップロードの操作と、送信中の進捗表示です。
    private var uploadButton: some View {
        Button {
            send(.sessionUploadRequested(session.id))
        } label: {
            if uploadingSessionID == session.id {
                HStack(spacing: 7 * scale) {
                    ProgressView(value: uploadProgress ?? 0, total: 1)
                        .progressViewStyle(.linear)
                        .frame(width: 72 * scale)
                    Text(uploadProgress ?? 0, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                }
                    .frame(minWidth: 112 * scale)
            } else {
                Label("history.upload.button", systemImage: "icloud.and.arrow.up")
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(uploadingSessionID != nil)
        .accessibilityIdentifier("macos-history-upload-\(session.id.rawValue.uuidString)")
    }
}
#endif
