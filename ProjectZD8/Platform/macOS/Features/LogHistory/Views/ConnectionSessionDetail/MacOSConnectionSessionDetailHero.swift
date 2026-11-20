#if os(macOS)
import SwiftUI

/// macOS のセッション詳細で、車両と Raw ログ保管状態を示す主カードです。
struct MacOSConnectionSessionDetailHero: View {
    /// 表示対象の接続セッションです。車両名・開始日時・状態・車種コード・ID を読みます。
    let session: ConnectionSession
    /// 画面サイズに対応する表示倍率です。
    let scale: CGFloat
    /// 取得元端末の表示文字列です。
    let acquisitionDeviceText: String
    /// セッションの現在状態のローカライズキーです。
    let statusKey: String

    /// アイコン、識別情報、状態の列を横に並べて描画します。
    ///
    /// 責務: 1件のセッションの識別情報と状態を、角丸の主カードとして描画します。
    var body: some View {
        HStack(spacing: 22 * scale) {
            Image(systemName: "waveform.path.ecg.rectangle.fill")
                .font(.system(size: 34 * scale, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 78 * scale, height: 78 * scale)
                .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 23 * scale, style: .continuous))
            identity
            Spacer(minLength: 20 * scale)
            statusColumn
        }
        .padding(25 * scale)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28 * scale, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 28 * scale, style: .continuous).stroke(Color.primary.opacity(0.08)) }
    }

    /// 見出し、車両名、開始日時、取得元端末の列です。
    private var identity: some View {
        VStack(alignment: .leading, spacing: 6 * scale) {
            Text("history.training.badge")
                .font(.system(size: 10 * scale, weight: .bold, design: .rounded))
                .tracking(1.8 * scale)
                .foregroundStyle(.tint)
            Text(session.vehicle?.name ?? String(localized: "history.vehicle.pending"))
                .font(.system(size: 30 * scale, weight: .bold, design: .rounded))
            Text(session.startedAt, format: .dateTime.year().month().day().hour().minute())
                .font(.system(size: 12 * scale, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
            Label(acquisitionDeviceText, systemImage: "laptopcomputer.and.iphone")
                .font(.system(size: 10.5 * scale, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    /// 車種バッジ、状態のラベル、セッション ID の列です。
    private var statusColumn: some View {
        VStack(alignment: .trailing, spacing: 7 * scale) {
            if let modelCode = session.distanceSourceModelCode {
                VehicleModelBadge(modelCode: modelCode)
            }
            Label(LocalizedStringKey(statusKey), systemImage: session.status == .completed ? "checkmark.seal.fill" : "clock.badge.exclamationmark")
                .font(.system(size: 12 * scale, weight: .bold))
                .foregroundStyle(session.status == .completed ? Color.green : Color.orange)
                .padding(.horizontal, 13 * scale)
                .padding(.vertical, 8 * scale)
                .background(Color.primary.opacity(0.055), in: Capsule())
            Text(session.id.rawValue.uuidString.uppercased())
                .font(.system(size: 9 * scale, design: .monospaced))
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
        }
    }
}
#endif
