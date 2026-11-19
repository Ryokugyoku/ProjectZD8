#if os(iOS)
import SwiftUI

/// 未接続時のホームで、デフォルトアダプターの状態と接続・設定の主要操作をまとめたカードです。
struct IOSHomeAdapterCard: View {
    /// 表示するアダプターカードの内容です。
    let content: HomeAdapterCardContent
    /// 接続先を添えて接続開始を通知するクロージャです。
    let onConnect: (OBDConnectionEndpoint) -> Void
    /// アダプター設定の開始を通知するクロージャです。
    let onSetupAdapter: () -> Void

    /// アダプターの記号、名称、検出状態、主要操作を縦に並べます。
    ///
    /// 責務: 1件のアダプターカード内容を枠付きのカードへ描画します。
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: IOSHomeMetrics.cardCornerRadius, style: .continuous)
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
        .padding(IOSHomeMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: shape)
        .overlay { shape.stroke(Color.accentColor.opacity(IOSHomeMetrics.cardStrokeOpacity), lineWidth: 1) }
        .shadow(
            color: Color.black.opacity(IOSHomeMetrics.cardShadowOpacity),
            radius: IOSHomeMetrics.cardShadowRadius,
            y: IOSHomeMetrics.cardShadowOffsetY
        )
    }

    /// デフォルトアダプターの検出可否を示す記号です。
    private var adapterSymbol: some View {
        ZStack {
            Circle().fill(Color.accentColor.opacity(0.13))
            Circle().stroke(Color.accentColor.opacity(0.28), lineWidth: 1)
            Image(systemName: content.adapterSymbol)
                .font(.system(size: IOSHomeMetrics.adapterSymbolFontSize, weight: .semibold))
                .foregroundStyle(.tint)
        }
        .frame(width: IOSHomeMetrics.adapterSymbolSize, height: IOSHomeMetrics.adapterSymbolSize)
        .accessibilityHidden(true)
    }

    /// デフォルトアダプターの名称と検出状態です。
    private var adapterIdentity: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("home.adapter.eyebrow")
                .font(.system(.caption2, design: .rounded, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(.secondary)
            adapterTitle
                .font(.system(.title2, design: .rounded, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
            Label(LocalizedStringKey(content.statusKey), systemImage: content.statusSymbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(content.isDetected ? Color.green : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
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
        Button {
            if let endpoint { onConnect(endpoint) }
        } label: {
            Text("home.action.connect")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(endpoint == nil)
        .accessibilityIdentifier("ios-home-connect")
    }

    /// アダプター設定へ進むボタンと補足です。
    private var setupAdapterButton: some View {
        VStack(alignment: .leading, spacing: 9) {
            Button(action: onSetupAdapter) {
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
#endif
