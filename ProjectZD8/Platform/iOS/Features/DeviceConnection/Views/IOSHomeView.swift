#if os(iOS)
import SwiftUI

/// iOS HOMEで接続準備とアダプター設定導線を描画します。
struct IOSHomeView: View {
    /// HOMEに表示するデフォルトアダプター状態です。
    let state: IOSHomeState

    /// HOMEの操作をAppShellへ通知するクロージャです。
    let send: (IOSHomeAction) -> Void

    /// 現在のDynamic Type設定です。
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// iPhoneの片手操作と文字拡大に追従する接続準備画面を提供します。
    ///
    /// 責務: デフォルトアダプターの接続可否を主要操作と短い状態説明へ反映したiOS HOMEを描画します。
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                brandHeader
                heading
                adapterCard
                futureFeatureCard
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ios-home-screen")
    }

    /// 画面幅と文字サイズに応じた左右余白です。
    private var horizontalPadding: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 16 : 20
    }

    /// 製品名とモバイル向けコンセプトを示すブランド表示です。
    private var brandHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.58)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: Color.accentColor.opacity(0.25), radius: 10, y: 4)

                Image(systemName: "car.side.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 2) {
                Text("Project ZD8")
                    .font(.system(.headline, design: .rounded, weight: .bold))

                Text("ios.shell.tagline")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    /// HOMEの目的を短い見出しとして示します。
    private var heading: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("home.eyebrow")
                .font(.system(.caption2, design: .rounded, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(.tint)

            Text("home.title")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)

            Text("home.subtitle")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// デフォルトアダプター状態と主要操作を縦方向のカードへまとめます。
    private var adapterCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 16) {
                    adapterSymbol
                    adapterIdentity
                }

                VStack(alignment: .leading, spacing: 14) {
                    adapterSymbol
                    adapterIdentity
                }
            }

            primaryAction
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.08), radius: 18, y: 8)
    }

    /// デフォルトアダプターの現在の検出可否を示すシンボルです。
    private var adapterSymbol: some View {
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
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.tint)
        }
        .frame(width: 72, height: 72)
        .accessibilityHidden(true)
    }

    /// デフォルトアダプターの名称と検出状態です。
    private var adapterIdentity: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("home.adapter.eyebrow")
                .font(.system(.caption2, design: .rounded, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(.secondary)

            Text(adapterTitle)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)

            Label(adapterStatusText, systemImage: adapterStatusSymbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(state.defaultAdapterAvailability.isDetected ? Color.green : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// デフォルトアダプターの接続可否に応じた主要操作です。
    private var primaryAction: some View {
        VStack(alignment: .leading, spacing: 9) {
            if state.isConnectionActive {
                Button("home.action.disconnect", role: .destructive) {
                    send(.vehicleDisconnectionRequested)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("ios-home-disconnect")
                .disabled(state.isDisconnecting)
            } else if let endpoint = state.defaultAdapterAvailability.connectionEndpoint {
                Button("home.action.connect") {
                    send(.vehicleConnectionRequested(endpoint))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("ios-home-connect")
            } else {
                Button {
                    send(.adapterSetupRequested)
                } label: {
                    Label("home.action.setup_adapter", systemImage: "arrow.right.circle.fill")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 28)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("ios-home-setup-adapter")

                Text("home.action.setup_hint")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 今後の機能追加余地を控えめに示します。
    private var futureFeatureCard: some View {
        Label("home.future.caption", systemImage: "gauge.with.dots.needle.33percent")
            .font(.footnote.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
