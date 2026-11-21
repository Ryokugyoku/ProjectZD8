#if os(macOS)
import SwiftUI

/// macOS のセッション詳細で、観測済みの停止理由とユーザーの確認状態を表示します。
struct MacOSConnectionSessionDetailStopReviewCard: View {
    /// 画面サイズに対応する表示倍率です。
    let scale: CGFloat
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
                .font(.system(size: 12 * scale, weight: .semibold))
                .foregroundStyle(.green)
                .padding(15 * scale)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.07), in: RoundedRectangle(cornerRadius: 18 * scale, style: .continuous))
        }
    }

    /// 停止理由の本文と確認ボタンを横に並べたカードです。
    private var reviewCard: some View {
        HStack(spacing: 14 * scale) {
            WarningTriangleIcon(size: 20 * scale)
            VStack(alignment: .leading, spacing: 4 * scale) {
                Text("history.stop_review.card.title")
                    .font(.system(size: 14 * scale, weight: .bold, design: .rounded))
                Text(LocalizedStringKey(messageKey))
                    .font(.system(size: 11 * scale))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12 * scale)
            Button("history.stop_review.card.action", action: onReview)
                .buttonStyle(.borderedProminent)
                .tint(.orange)
        }
        .padding(17 * scale)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 18 * scale, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18 * scale, style: .continuous).stroke(Color.orange.opacity(0.22)) }
    }
}
#endif
