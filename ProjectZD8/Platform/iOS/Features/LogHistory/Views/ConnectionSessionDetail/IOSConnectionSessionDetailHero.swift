#if os(iOS)
import SwiftUI

/// iPhone のセッション詳細で、車両・日時・Raw ログの概念を示す主カードです。
struct IOSConnectionSessionDetailHero: View {
    /// 表示対象の接続セッションです。車両名・開始日時・車種コード・ID を読みます。
    let session: ConnectionSession
    /// 取得元端末の表示文字列です。
    let acquisitionDeviceText: String

    /// 見出し、車両名、日時、取得元端末、車種バッジ、セッション ID を描画します。
    ///
    /// 責務: 1件のセッションの識別情報を、角丸の主カードとして描画します。
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                identity
                Spacer(minLength: 16)
                badges
            }
            Text("history.raw.subtitle")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Text(session.id.rawValue.uuidString.uppercased())
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.primary.opacity(0.08)) }
    }

    /// 見出し、車両名、開始日時、取得元端末の列です。
    private var identity: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("history.raw.badge")
                .font(.caption.weight(.bold))
                .tracking(1.5)
                .foregroundStyle(.tint)
            Text(session.vehicle?.name ?? String(localized: "history.vehicle.pending"))
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text(session.startedAt, format: .dateTime.year().month().day().hour().minute())
                .font(.subheadline.monospaced().weight(.semibold))
                .foregroundStyle(.secondary)
            Label(acquisitionDeviceText, systemImage: "laptopcomputer.and.iphone")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    /// 車種バッジと Raw ログのアイコンの列です。
    private var badges: some View {
        VStack(spacing: 8) {
            if let modelCode = session.distanceSourceModelCode {
                VehicleModelBadge(modelCode: modelCode)
            }
            Image(systemName: "waveform.path.ecg.rectangle.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 66, height: 66)
                .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}
#endif
