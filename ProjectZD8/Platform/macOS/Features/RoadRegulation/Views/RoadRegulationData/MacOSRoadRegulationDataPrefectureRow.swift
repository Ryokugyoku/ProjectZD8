#if os(macOS)
import SwiftUI

/// macOSの交通規制データの管理画面で、都道府県1行の状態・版の詳細・進み具合・失敗・操作を描画します。
///
/// 出すボタンとその可否・文言キーは `RoadRegulationPrefectureRowContent` が、値の文言は
/// `RoadRegulationSettingsTextFormatter` が決め、この型は描画と操作の通知だけを行います。
struct MacOSRoadRegulationDataPrefectureRow: View {
    /// 行に出す内容です。
    let content: RoadRegulationPrefectureRowContent
    /// 値を差し込む文言を作る型です。
    let formatter: RoadRegulationSettingsTextFormatter
    /// 取得・更新が押されたことを通知するクロージャです。
    let download: () -> Void
    /// 削除が押されたことを通知するクロージャです(確認は画面ルートが出します)。
    let remove: () -> Void
    /// 中止が押されたことを通知するクロージャです。
    let cancel: () -> Void
    /// ウインドウ寸法に応じた拡大率を持つ寸法です。
    let metrics: MacOSAppShellMetrics

    /// 見出しと操作を横に、詳細・進み具合・失敗をその下に並べた行を提供します。
    ///
    /// 責務: 行の内容が示す要素だけを順に描画します。
    var body: some View {
        VStack(alignment: .leading, spacing: MacOSRoadRegulationDataMetrics.rowSpacing * metrics.scale) {
            HStack(spacing: MacOSRoadRegulationDataMetrics.rowTitleSpacing * metrics.scale) {
                titleRow
                Spacer(minLength: 0)
                buttons
            }
            if let dataset = content.dataset {
                details(dataset)
            }
            if let phaseKey = content.phaseKey {
                progress(phaseKey: phaseKey)
            }
            if let failureKey = content.failureKey {
                failure(key: failureKey)
            }
        }
        .padding(.vertical, MacOSRoadRegulationDataMetrics.rowVerticalPadding * metrics.scale)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("macos-road-regulation-row-\(content.id)")
    }

    /// 都道府県名と状態のバッジを並べた見出しです。
    private var titleRow: some View {
        HStack(spacing: MacOSRoadRegulationDataMetrics.rowTitleSpacing * metrics.scale) {
            Text(LocalizedStringKey(content.nameKey))
                .font(.system(size: MacOSRoadRegulationDataMetrics.rowTitleFontSize * metrics.scale, weight: .semibold, design: .rounded))
            Text(LocalizedStringKey(content.statusKey))
                .font(.system(size: MacOSRoadRegulationDataMetrics.badgeFontSize * metrics.scale, weight: .semibold))
                .foregroundStyle(.tint)
                .padding(.horizontal, MacOSRoadRegulationDataMetrics.badgeHorizontalPadding * metrics.scale)
                .padding(.vertical, MacOSRoadRegulationDataMetrics.badgeVerticalPadding * metrics.scale)
                .background(Color.accentColor.opacity(MacOSRoadRegulationDataMetrics.badgeFillOpacity), in: Capsule())
        }
    }

    /// 取得・更新・削除・中止のボタンです。
    private var buttons: some View {
        HStack(spacing: MacOSRoadRegulationDataMetrics.buttonSpacing * metrics.scale) {
            if content.showsDownload {
                Button(LocalizedStringKey(content.downloadButtonKey), action: download)
                    .disabled(!content.canStartDownload)
                    .accessibilityIdentifier("macos-road-regulation-download-\(content.id)")
            }
            if content.showsRemove {
                Button("road_regulation.data.remove", role: .destructive, action: remove)
                    .disabled(!content.canRemove)
                    .accessibilityIdentifier("macos-road-regulation-remove-\(content.id)")
            }
            if content.showsCancel {
                Button("road_regulation.data.cancel", action: cancel)
                    .accessibilityIdentifier("macos-road-regulation-cancel-\(content.id)")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    /// 版の基準月・件数・捨てた件数・取得日を並べた詳細を作ります。
    ///
    /// 責務: 版の値を文言にして、小さな補助の文字で横に並べます。
    /// - Parameter dataset: 有効な版。
    /// - Returns: 版の詳細。
    private func details(_ dataset: RoadRegulationDataset) -> some View {
        HStack(spacing: MacOSRoadRegulationDataMetrics.detailSpacing * metrics.scale) {
            Text(verbatim: formatter.dataMonthLine(dataset))
            Text(verbatim: formatter.regulationCountLine(dataset))
            Text(verbatim: formatter.rejectedCountLine(dataset))
            Text(verbatim: formatter.downloadedAtLine(dataset))
        }
        .font(.system(size: MacOSRoadRegulationDataMetrics.captionFontSize * metrics.scale))
        .foregroundStyle(.secondary)
    }

    /// 取り込みの段階と進み具合を作ります。
    ///
    /// 責務: 進み具合が分かれば割合の棒と百分率を、分からなければ進行中の棒を、段階の文言と並べます。
    /// - Parameter phaseKey: 段階の文言キー。
    /// - Returns: 進み具合の表示。
    private func progress(phaseKey: String) -> some View {
        VStack(alignment: .leading, spacing: MacOSRoadRegulationDataMetrics.progressSpacing * metrics.scale) {
            if let fraction = content.progressFraction {
                ProgressView(value: fraction)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
            }
            HStack(spacing: MacOSRoadRegulationDataMetrics.progressSpacing * metrics.scale) {
                Text(LocalizedStringKey(phaseKey))
                if let fraction = content.progressFraction {
                    Text(verbatim: formatter.progressPercentText(fraction))
                        .monospacedDigit()
                }
            }
            .font(.system(size: MacOSRoadRegulationDataMetrics.captionFontSize * metrics.scale))
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("macos-road-regulation-progress-\(content.id)")
    }

    /// 最後の失敗の1行を作ります。アイコンだけをオレンジで強調します。
    ///
    /// 責務: 失敗の文言キーを `LocalizedStringKey` へ変換し、注意の印と並べます。
    /// - Parameter key: 失敗の文言キー。
    /// - Returns: 失敗の1行。
    private func failure(key: String) -> some View {
        Label {
            Text(LocalizedStringKey(key))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.orange)
        }
        .font(.system(size: MacOSRoadRegulationDataMetrics.captionFontSize * metrics.scale))
        .accessibilityIdentifier("macos-road-regulation-failure-\(content.id)")
    }
}
#endif
