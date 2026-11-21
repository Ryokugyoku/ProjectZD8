#if os(iOS)
import SwiftUI

/// 1件のセッションに現在必要な手動アップロード操作(通常、再試行、進捗)です。
struct IOSConnectionHistoryVehicleSessionsUploadAction: View {
    /// アップロード操作を表示するセッションです。
    let session: ConnectionSession
    /// 送信中のセッションIDです。どれも送信中でなければ `nil`。
    let uploadingSessionID: ConnectionSessionID?
    /// 送信中アップロードの進捗(0〜1)です。
    let uploadProgress: Double?
    /// アップロード操作をApplicationへ通知します。
    let send: (ConnectionHistoryAction) -> Void

    /// 現在の転送状態に対応する見た目のアップロードボタンを描画します。
    ///
    /// 責務: 1件の手動送信可能なセッションを、表示の種類に応じたアップロード操作へ配置します。
    var body: some View {
        Button {
            send(.sessionUploadRequested(session.id))
        } label: {
            switch IOSConnectionHistoryUploadActionStyle.style(for: session, uploadingSessionID: uploadingSessionID) {
            case .inProgress: progressLabel
            case .retry: retryLabel
            case .upload: uploadLabel
            }
        }
        .buttonStyle(.plain)
        .disabled(uploadingSessionID != nil)
        .accessibilityIdentifier("ios-history-upload-\(session.id.rawValue.uuidString)")
    }

    /// 送信中の進捗バーと割合です。
    private var progressLabel: some View {
        VStack(spacing: 6) {
            ProgressView(value: uploadProgress ?? 0, total: 1)
                .progressViewStyle(.linear)
            HStack {
                Text("history.upload.in_progress")
                Spacer()
                Text(uploadProgress ?? 0, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
            }
            .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 15)
        .padding(.vertical, 10)
    }

    /// 転送失敗後の再試行の案内です。
    private var retryLabel: some View {
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
    }

    /// 通常のアップロード操作のラベルです。
    private var uploadLabel: some View {
        Label("history.upload.button", systemImage: "icloud.and.arrow.up")
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .foregroundStyle(.tint)
    }
}
#endif
