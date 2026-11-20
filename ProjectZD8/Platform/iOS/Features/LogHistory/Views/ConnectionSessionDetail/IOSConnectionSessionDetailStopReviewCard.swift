#if os(iOS)
import SwiftUI

/// iPhone のセッション詳細で、観測済みの停止理由とユーザーの確認状態を表示します。
struct IOSConnectionSessionDetailStopReviewCard: View {
    /// 停止の確認が必要なセッションかを示します。
    let needsStopReview: Bool
    /// ユーザーが停止を自分の操作として承認済みかを示します。
    let isUserAccepted: Bool
    /// 確認カードの本文のローカライズキーです。
    let messageKey: String
    /// 停止の確認の要求を送出します。
    let onReview: () -> Void

    /// 確認が必要なら確認カードを、承認済みなら承認済みの表示を描画します。
    ///
    /// 責務: 停止の確認状態に応じて、確認カード・承認済み表示・非表示のいずれかを描画します。
    var body: some View {
        if needsStopReview {
            reviewCard
        } else if isUserAccepted {
            Label("history.stop_review.accepted", systemImage: "checkmark.seal.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)
                .padding(15)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    /// 停止理由の本文と確認ボタンを持つカードです。
    private var reviewCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 10) {
                WarningTriangleIcon(size: 19)
                Text("history.stop_review.card.title")
                    .font(.headline)
            }
            Text(LocalizedStringKey(messageKey))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("history.stop_review.card.action", action: onReview)
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(17)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.orange.opacity(0.22)) }
    }
}
#endif
