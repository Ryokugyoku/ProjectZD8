#if os(macOS)
import SwiftUI

/// 未接続時のmacOSホームで、デフォルトアダプターの状態と接続・設定の主要操作をまとめたカードです。
struct MacOSHomeAdapterCard: View {
    /// 表示するアダプターカードの内容です。
    let content: HomeAdapterCardContent
    /// カード内部を縦方向へ並べる必要があるかどうかです。
    let isCompact: Bool
    /// 画面サイズに対応する表示倍率です。
    let scale: CGFloat
    /// 接続先を添えて接続開始を通知するクロージャです。
    let onConnect: (OBDConnectionEndpoint) -> Void
    /// アダプター設定の開始を通知するクロージャです。
    let onSetupAdapter: () -> Void

    /// ウインドウ幅に応じて、アダプターの情報と主要操作を横並びまたは縦並びで描画します。
    ///
    /// 責務: 1件のアダプターカード内容を枠付きのカードへ描画します。
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 28 * scale, style: .continuous)
        Group {
            if isCompact {
                VStack(alignment: .leading, spacing: 24 * scale) {
                    adapterIdentity
                    primaryAction
                }
            } else {
                HStack(alignment: .center, spacing: 34 * scale) {
                    adapterIdentity
                    Spacer(minLength: 20 * scale)
                    primaryAction
                }
            }
        }
        .padding(28 * scale)
        .frame(maxWidth: .infinity, minHeight: 220 * scale, alignment: .leading)
        .background(.regularMaterial, in: shape)
        .overlay { shape.stroke(Color.accentColor.opacity(0.18), lineWidth: 1) }
        .shadow(color: Color.black.opacity(0.08), radius: 22 * scale, y: 12 * scale)
    }

    /// デフォルトアダプターの記号、名称、検出状態です。
    private var adapterIdentity: some View {
        HStack(alignment: .center, spacing: 20 * scale) {
            adapterSymbol
            VStack(alignment: .leading, spacing: 8 * scale) {
                Text("home.adapter.eyebrow")
                    .font(.system(size: 10 * scale, weight: .bold, design: .rounded))
                    .tracking(1.3 * scale)
                    .foregroundStyle(.secondary)
                adapterTitle
                    .font(.system(size: 24 * scale, weight: .bold, design: .rounded))
                    .lineLimit(2)
                Label(LocalizedStringKey(content.statusKey), systemImage: content.statusSymbol)
                    .font(.system(size: 12 * scale, weight: .semibold))
                    .foregroundStyle(content.isDetected ? Color.green : Color.secondary)
            }
        }
    }

    /// デフォルトアダプターの検出可否を示す記号です。
    private var adapterSymbol: some View {
        ZStack {
            Circle().fill(Color.accentColor.opacity(0.13))
            Circle().stroke(Color.accentColor.opacity(0.28), lineWidth: 1)
            Image(systemName: content.adapterSymbol)
                .font(.system(size: 32 * scale, weight: .semibold))
                .foregroundStyle(.tint)
        }
        .frame(width: 82 * scale, height: 82 * scale)
        .accessibilityHidden(true)
    }

    /// 設定済みならアダプター名をそのまま、未設定なら未設定の文言を出します。
    private var adapterTitle: Text {
        if let adapterName = content.adapterName {
            Text(verbatim: adapterName)
        } else {
            Text(LocalizedStringKey(HomeAdapterCardContent.notConfiguredTitleKey))
        }
    }

    /// 検出状態に応じた主要操作です。
    @ViewBuilder
    private var primaryAction: some View {
        switch content.primaryAction {
        case let .connect(endpoint):
            connectButton(endpoint)
        case .setupAdapter:
            setupAdapterButton
        }
    }

    /// 接続を開始するボタンです。接続先がない時は押せない状態で出します。
    ///
    /// 責務: 1件の接続先を接続開始の操作へ結び付けます。
    /// - Parameter endpoint: 接続先。`nil` ならボタンを無効にします。
    /// - Returns: 接続ボタン。
    private func connectButton(_ endpoint: OBDConnectionEndpoint?) -> some View {
        Button("home.action.connect") {
            if let endpoint { onConnect(endpoint) }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(endpoint == nil)
        .accessibilityIdentifier("macos-home-connect")
    }

    /// アダプター設定へ進むボタンと補足です。
    private var setupAdapterButton: some View {
        VStack(alignment: .leading, spacing: 9 * scale) {
            Button(action: onSetupAdapter) {
                Label("home.action.setup_adapter", systemImage: "arrow.right.circle.fill")
                    .font(.system(size: 13 * scale, weight: .bold, design: .rounded))
                    .frame(minWidth: 190 * scale, minHeight: 30 * scale)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("macos-home-setup-adapter")
            Text("home.action.setup_hint")
                .font(.system(size: 10.5 * scale, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}
#endif
