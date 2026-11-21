#if os(iOS)
import SwiftUI

/// iOS設定画面の走行ルート記録カードで、記録の状態・概略の位置の注意・設定アプリへのリンクを描画します。
///
/// 何を出すかの判定は `RouteRecordingSettingsSection` が持ち、この型は描画と設定アプリを開く操作だけを行います。
struct IOSSettingsRouteRecordingStatusNotice: View {
    /// URLを開くシステムの操作です。
    @Environment(\.openURL) private var openURL

    /// 保存済みの設定と記録の状態です。
    let section: RouteRecordingSettingsSection

    /// 状態の文言と、必要な時だけ注意とリンクを並べた案内を提供します。
    ///
    /// 責務: 状態を常に示し、警告ならアイコンだけをオレンジで強調し、注意とリンクは区画の判定どおりに出します。
    var body: some View {
        VStack(alignment: .leading, spacing: IOSSettingsMetrics.routeRecordingNoticeSpacing) {
            noticeRow(key: section.status.localizationKey, systemImage: statusSymbol, isWarning: section.isWarning)
                .accessibilityIdentifier("ios-settings-route-recording-status")
            if section.showsReducedAccuracyNotice {
                noticeRow(key: RouteRecordingSettingsSection.reducedAccuracyNoticeKey, systemImage: "location.circle", isWarning: true)
            }
            if section.showsSystemSettingsLink {
                Button(LocalizedStringKey(RouteRecordingSettingsSection.openSystemSettingsKey), action: openSystemSettings)
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderless)
            }
        }
        .padding(IOSSettingsMetrics.noticePadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.primary.opacity(IOSSettingsMetrics.noticeFillOpacity),
            in: RoundedRectangle(cornerRadius: IOSSettingsMetrics.noticeCornerRadius, style: .continuous)
        )
    }

    /// 状態のアイコンです。警告なら注意の印、それ以外は情報の印です。
    private var statusSymbol: String {
        section.isWarning ? "exclamationmark.triangle.fill" : "info.circle"
    }

    /// アイコンと文言を並べた1行を作ります。
    ///
    /// 責務: 文言キーを `LocalizedStringKey` へ変換し、警告の時だけアイコンをオレンジにします。
    /// - Parameters:
    ///   - key: 文言のローカライズキー。
    ///   - systemImage: アイコンのSF Symbol名。
    ///   - isWarning: 警告として強調するなら `true`。
    /// - Returns: 案内の1行。
    private func noticeRow(key: String, systemImage: String, isWarning: Bool) -> some View {
        Label {
            Text(LocalizedStringKey(key))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(isWarning ? Color.orange : Color.secondary)
        }
        .font(.caption)
    }

    /// システムの設定アプリでこのアプリの設定を開きます。
    ///
    /// 責務: 設定アプリのURLを作り、システムのURLを開く操作へ渡します。
    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}
#endif
