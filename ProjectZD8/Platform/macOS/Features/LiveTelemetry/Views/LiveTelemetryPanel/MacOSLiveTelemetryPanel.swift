#if os(macOS)
import SwiftUI

/// macOSホームへ差し込むリアルタイム表示パネルです。状態バナー、再試行、主要値、車種専用値、分類一覧の順に並べます。
struct MacOSLiveTelemetryPanel: View {
    /// Applicationが公開するPID読取状態です。
    let state: LiveTelemetryState
    /// PID読取操作の通知先です。
    let send: (LiveTelemetryAction) -> Void
    /// 現在のウインドウ寸法に対応する表示寸法です。
    let metrics: MacOSAppShellMetrics
    /// 分類一覧で選択している分類です。表示時に表示できる分類へ補正します。
    @State private var selectedCategory: OBDPIDCategory = .engine
    /// PID説明のポップオーバーを表示しているPIDです。
    @State private var helpSampleID: OBDPIDSample.ID?

    /// 表示する内容がある時だけパネルを描画します。
    ///
    /// 責務: 共通の表示内容に従って部品を配置し、分類の選択、PID説明、再試行操作を接続します。
    var body: some View {
        let content = LiveTelemetryPanelContent(state: state)
        if !content.isEmpty {
            VStack(alignment: .leading, spacing: 20 * metrics.scale) {
                if let banner = content.banner {
                    MacOSLiveTelemetryPanelStatusBanner(banner: banner, scale: metrics.scale)
                }
                if content.showsRetry {
                    retryButton
                }
                if content.showsSamples {
                    sampleSections(content)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("macos-live-telemetry")
        }
    }

    /// 失敗後の再取得操作です。
    private var retryButton: some View {
        Button {
            send(.retryRequested)
        } label: {
            Label("telemetry.retry", systemImage: "arrow.clockwise")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .accessibilityIdentifier("macos-live-telemetry-retry")
    }

    /// 取得中の値を主要値、車種専用値、分類一覧の順に並べます。
    ///
    /// 責務: 1件の表示内容を、値の区画の部品へ振り分けます。
    /// - Parameter content: 現在のパネル表示内容。
    /// - Returns: 値の区画を縦に並べた表示。
    @ViewBuilder
    private func sampleSections(_ content: LiveTelemetryPanelContent) -> some View {
        MacOSLiveTelemetryPanelPrimaryDashboard(
            samples: content.groups.primarySamples,
            respondingPIDCount: content.respondingPIDCount,
            scale: metrics.scale,
            helpSampleID: helpSampleID,
            onHelpRequested: showHelp,
            onHelpDismissed: dismissHelp
        )
        if !content.groups.vehicleSpecificSamples.isEmpty {
            MacOSLiveTelemetryPanelVehicleSpecificSection(
                samples: content.groups.vehicleSpecificSamples,
                modelCode: content.groups.vehicleSpecificModelCode,
                scale: metrics.scale,
                helpSampleID: helpSampleID,
                onHelpRequested: showHelp,
                onHelpDismissed: dismissHelp
            )
        }
        MacOSLiveTelemetryPanelCategoryWorkspace(
            groups: content.groups,
            selectedCategory: content.groups.resolvedCategory(selectedCategory),
            scale: metrics.scale,
            helpSampleID: helpSampleID,
            onSelectCategory: { selectedCategory = $0 },
            onHelpRequested: showHelp,
            onHelpDismissed: dismissHelp
        )
    }

    /// 指定したPIDの説明ポップオーバーを開きます。
    ///
    /// 責務: 部品から通知された1件のPIDを説明の表示対象にします。
    /// - Parameter sample: 説明するPIDサンプル。
    private func showHelp(_ sample: OBDPIDSample) {
        helpSampleID = sample.id
    }

    /// 閉じたポップオーバーのPIDが表示対象のままなら、表示対象を解除します。
    ///
    /// 責務: 別のPIDの説明へ切り替えた直後に古いポップオーバーの閉鎖通知で新しい表示を消さないよう、対象を照合して解除します。
    /// - Parameter sample: ポップオーバーを閉じたPIDサンプル。
    private func dismissHelp(_ sample: OBDPIDSample) {
        guard helpSampleID == sample.id else { return }
        helpSampleID = nil
    }
}
#endif
