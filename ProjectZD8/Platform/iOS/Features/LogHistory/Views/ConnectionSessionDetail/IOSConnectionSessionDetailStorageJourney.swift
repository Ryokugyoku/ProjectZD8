#if os(iOS)
import SwiftUI

/// iPhone のセッション詳細で、iPhone と CloudKit の Raw ログ保管状態を順に表示します。
///
/// 状態の文言キーと色は一覧の `ConnectionHistoryRawStatusBadge` と色調が異なるため、詳細画面の既存の対応をそのまま持ちます。
struct IOSConnectionSessionDetailStorageJourney: View {
    /// 現在端末の Raw ログ保管状態です。
    let localState: ConnectionSessionLocalRawState
    /// CloudKit への転送状態です。
    let cloudState: ConnectionSessionCloudSyncState

    /// 見出しと、iPhone・iCloud の2行を描画します。
    ///
    /// 責務: 2つの保管先の状態を、アイコンと状態ラベルを持つ行としてカードに並べます。
    var body: some View {
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
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.primary.opacity(0.08)) }
    }

    /// 1段階の保管先と状態を描画します。
    ///
    /// 責務: 1件の保管先状態をアイコンと状態ラベルを持つ行へ変換します。
    /// - Parameters:
    ///   - titleKey: 保管先のローカライズキー。
    ///   - statusKey: 現在状態のローカライズキー。
    ///   - systemImage: 保管先を示す SF Symbol。
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

    /// 現在端末の Raw 保管状態に対応するローカライズキーです。
    private var localStateKey: LocalizedStringKey {
        switch localState {
        case .empty: "history.raw.local.empty"
        case .available: "history.raw.local.available"
        case .removed: "history.raw.local.removed"
        }
    }

    /// 現在端末の Raw 保管状態に対応する色です。
    private var localStateColor: Color {
        switch localState {
        case .empty: .secondary
        case .available: .blue
        case .removed: .gray
        }
    }

    /// CloudKit 転送状態に対応するローカライズキーです。
    private var cloudStateKey: LocalizedStringKey {
        switch cloudState {
        case .notUploaded: "history.raw.cloud.not_uploaded"
        case .pending: "history.raw.cloud.pending"
        case .uploaded: "history.raw.cloud.uploaded"
        case .failed: "history.raw.cloud.failed"
        }
    }

    /// CloudKit 転送状態に対応する色です。
    private var cloudStateColor: Color {
        switch cloudState {
        case .notUploaded: .secondary
        case .pending: .orange
        case .uploaded: .cyan
        case .failed: .red
        }
    }
}
#endif
