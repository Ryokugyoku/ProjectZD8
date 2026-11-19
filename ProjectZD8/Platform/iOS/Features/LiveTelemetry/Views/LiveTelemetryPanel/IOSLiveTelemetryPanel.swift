#if os(iOS)
import SwiftUI

/// iOSホームへ差し込むリアルタイム表示パネルです。状態バナー、再試行、主要値、車種専用値、分類一覧の順に並べます。
struct IOSLiveTelemetryPanel: View {
    /// Applicationが公開するPID読取状態です。
    let state: LiveTelemetryState
    /// PID読取操作の通知先です。
    let send: (LiveTelemetryAction) -> Void
    /// 説明シートへ表示する現在のPIDです。
    @State private var helpSample: OBDPIDSample?

    /// 表示する内容がある時だけパネルを描画します。
    ///
    /// 責務: 共通の表示内容に従って部品を配置し、説明シートと再試行操作を接続します。
    var body: some View {
        let content = LiveTelemetryPanelContent(state: state)
        if !content.isEmpty {
            VStack(alignment: .leading, spacing: IOSLiveTelemetryPanelMetrics.sectionSpacing) {
                if let banner = content.banner {
                    IOSLiveTelemetryPanelStatusBanner(banner: banner)
                }
                if content.showsRetry {
                    retryButton
                }
                if content.showsSamples {
                    sampleSections(content)
                }
            }
            .sheet(item: $helpSample) { sample in
                IOSLiveTelemetryPanelHelpSheet(content: LiveTelemetryPIDHelpContent(sample: sample)) {
                    helpSample = nil
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("ios-live-telemetry")
        }
    }

    /// 失敗後の再取得操作です。
    private var retryButton: some View {
        Button {
            send(.retryRequested)
        } label: {
            Label("telemetry.retry", systemImage: "arrow.clockwise")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .accessibilityIdentifier("ios-live-telemetry-retry")
    }

    /// 取得中の値を主要値、車種専用値、分類一覧の順に並べます。
    ///
    /// 責務: 1件の表示内容を、値の区画の部品へ振り分けます。
    /// - Parameter content: 現在のパネル表示内容。
    /// - Returns: 値の区画を縦に並べた表示。
    @ViewBuilder
    private func sampleSections(_ content: LiveTelemetryPanelContent) -> some View {
        IOSLiveTelemetryPanelPrimaryDashboard(
            samples: content.groups.primarySamples,
            respondingPIDCount: content.respondingPIDCount,
            onHelp: showHelp
        )
        if !content.groups.vehicleSpecificSamples.isEmpty {
            IOSLiveTelemetryPanelVehicleSpecificSection(
                samples: content.groups.vehicleSpecificSamples,
                modelCode: content.groups.vehicleSpecificModelCode,
                onHelp: showHelp
            )
        }
        IOSLiveTelemetryPanelCategoryList(groups: content.groups)
    }

    /// 指定したPIDの説明シートを開きます。
    ///
    /// 責務: 部品から通知された1件のPIDを説明シートの表示対象にします。
    /// - Parameter sample: 説明するPIDサンプル。
    private func showHelp(_ sample: OBDPIDSample) {
        helpSample = sample
    }
}
#endif
