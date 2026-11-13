#if os(macOS)
import SwiftUI

/// macOS HOMEで接続準備とアダプター設定導線を描画します。
struct MacOSHomeView: View {
    /// HOMEに表示するデフォルトアダプター状態です。
    let state: MacOSHomeState

    /// HOMEの操作をAppShellへ通知するクロージャです。
    let send: (MacOSHomeAction) -> Void

    /// 現在のウインドウサイズに対応する表示寸法です。
    let metrics: MacOSAppShellMetrics

    /// 車載コックピットを意識した接続準備カードを提供します。
    ///
    /// 責務: デフォルトアダプターの接続可否を主要操作と状態説明へ反映したmacOS HOMEを描画します。
    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 26 * metrics.scale) {
                    header
                    adapterHero(isCompact: proxy.size.width < 720)
                    futureFeatureRail
                }
                .padding(.horizontal, 34 * metrics.scale)
                .padding(.vertical, 32 * metrics.scale)
                .frame(maxWidth: 1_120, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .scrollIndicators(.hidden)
            .background(homeBackground)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("macos-home-screen")
    }

    /// HOMEの現在地と役割を示す見出しです。
    private var header: some View {
        VStack(alignment: .leading, spacing: 7 * metrics.scale) {
            Text("home.eyebrow")
                .font(.system(size: 10 * metrics.scale, weight: .bold, design: .rounded))
                .tracking(1.8 * metrics.scale)
                .foregroundStyle(.tint)

            Text("home.title")
                .font(.system(size: 34 * metrics.scale, weight: .bold, design: .rounded))

            Text("home.subtitle")
                .font(.system(size: 14 * metrics.scale, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    /// HOME全体へ静かな奥行きを与える背景です。
    private var homeBackground: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            LinearGradient(
                colors: [Color.accentColor.opacity(0.10), Color.clear],
                startPoint: .topTrailing,
                endPoint: .center
            )
        }
        .ignoresSafeArea()
    }

    /// デフォルトアダプターの状態と主要操作を1枚のカードへまとめます。
    ///
    /// 責務: ウインドウ幅に応じて接続準備情報と主要操作を横並びまたは縦並びで描画します。
    /// - Parameter isCompact: カード内部を縦方向へ並べる必要があるかどうか。
    /// - Returns: 現在のデフォルト設定を強調する主要カード。
    @ViewBuilder
    private func adapterHero(isCompact: Bool) -> some View {
        Group {
            if isCompact {
                VStack(alignment: .leading, spacing: 24 * metrics.scale) {
                    adapterIdentity
                    primaryAction
                }
            } else {
                HStack(alignment: .center, spacing: 34 * metrics.scale) {
                    adapterIdentity
                    Spacer(minLength: 20 * metrics.scale)
                    primaryAction
                }
            }
        }
        .padding(28 * metrics.scale)
        .frame(maxWidth: .infinity, minHeight: 220 * metrics.scale, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28 * metrics.scale, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28 * metrics.scale, style: .continuous)
                .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.08), radius: 22 * metrics.scale, y: 12 * metrics.scale)
    }

    /// デフォルトアダプターの設定状態を名称と視覚記号で示します。
    private var adapterIdentity: some View {
        HStack(alignment: .center, spacing: 20 * metrics.scale) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.13))

                Circle()
                    .stroke(Color.accentColor.opacity(0.28), lineWidth: 1)

                Image(
                    systemName: state.defaultAdapterAvailability.isDetected
                        ? "cable.connector.horizontal"
                        : "cable.connector.slash"
                )
                    .font(.system(size: 32 * metrics.scale, weight: .semibold))
                    .foregroundStyle(.tint)
            }
            .frame(width: 82 * metrics.scale, height: 82 * metrics.scale)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8 * metrics.scale) {
                Text("home.adapter.eyebrow")
                    .font(.system(size: 10 * metrics.scale, weight: .bold, design: .rounded))
                    .tracking(1.3 * metrics.scale)
                    .foregroundStyle(.secondary)

                Text(adapterTitle)
                    .font(.system(size: 24 * metrics.scale, weight: .bold, design: .rounded))
                    .lineLimit(2)

                Label(adapterStatusText, systemImage: adapterStatusSymbol)
                    .font(.system(size: 12 * metrics.scale, weight: .semibold))
                    .foregroundStyle(state.defaultAdapterAvailability.isDetected ? Color.green : Color.secondary)
            }
        }
    }

    /// デフォルトアダプターの接続可否に応じた主要操作を描画します。
    private var primaryAction: some View {
        VStack(alignment: .leading, spacing: 9 * metrics.scale) {
            if state.isConnectionActive {
                Button("home.action.disconnect", role: .destructive) {
                    send(.vehicleDisconnectionRequested)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("macos-home-disconnect")
                .disabled(state.isDisconnecting)
            } else if state.defaultAdapterAvailability.isDetected {
                Button("home.action.connect") {
                    if let endpoint = state.connectionEndpoint {
                        send(.vehicleConnectionRequested(endpoint))
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("macos-home-connect")
                .disabled(state.connectionEndpoint == nil)
            } else {
                Button {
                    send(.adapterSetupRequested)
                } label: {
                    Label("home.action.setup_adapter", systemImage: "arrow.right.circle.fill")
                        .font(.system(size: 13 * metrics.scale, weight: .bold, design: .rounded))
                        .frame(minWidth: 190 * metrics.scale, minHeight: 30 * metrics.scale)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("macos-home-setup-adapter")

                Text("home.action.setup_hint")
                    .font(.system(size: 10.5 * metrics.scale, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 今後の機能追加余地を静かなプレースホルダーとして示します。
    private var futureFeatureRail: some View {
        HStack(spacing: 12 * metrics.scale) {
            Image(systemName: "gauge.with.dots.needle.33percent")
                .font(.system(size: 16 * metrics.scale, weight: .semibold))
                .foregroundStyle(.tint)

            Text("home.future.caption")
                .font(.system(size: 11.5 * metrics.scale, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .padding(16 * metrics.scale)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16 * metrics.scale, style: .continuous))
    }

    /// デフォルト設定の有無に対応する主要名称です。
    private var adapterTitle: LocalizedStringKey {
        if let defaultAdapterName = state.defaultAdapterAvailability.displayName {
            LocalizedStringKey(defaultAdapterName)
        } else {
            "home.adapter.not_configured"
        }
    }

    /// デフォルト候補の現在の検出状態を表す説明です。
    private var adapterStatusText: LocalizedStringKey {
        if state.defaultAdapterAvailability.isDetected {
            "home.adapter.detected"
        } else if state.defaultAdapterAvailability.hasDefaultAdapter {
            "home.adapter.not_detected"
        } else {
            "home.adapter.setup_required"
        }
    }

    /// デフォルト候補の現在の検出状態を表すSF Symbol名です。
    private var adapterStatusSymbol: String {
        if state.defaultAdapterAvailability.isDetected {
            "checkmark.circle.fill"
        } else {
            "exclamationmark.circle.fill"
        }
    }
}
#endif
