import SwiftUI

/// 3種のボタンスタイルが共有する外観(最小タップ領域・押下・無効・Reduce Motion)。
struct InsightButtonChrome: View {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    /// ボタンの塗り方。
    enum Kind {
        case primary
        case secondary
        case destructive
    }

    let configuration: ButtonStyleConfiguration
    let kind: Kind

    /// 外観を作る。
    ///
    /// 責務: ボタン設定と種別を受け取る。
    init(configuration: ButtonStyleConfiguration, kind: Kind) {
        self.configuration = configuration
        self.kind = kind
    }

    @Environment(\.colorScheme) private var colorScheme

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: InsightRadius.sm, style: .continuous)
    }

    private var foreground: Color {
        switch kind {
        case .primary: colorScheme == .dark ? .black : .white
        case .secondary: InsightPalette.accent
        case .destructive: .white
        }
    }

    var body: some View {
        configuration.label
            .font(InsightTypography.button)
            .foregroundStyle(foreground)
            .multilineTextAlignment(.center)
            .padding(.horizontal, InsightSpacing.lg)
            .padding(.vertical, InsightSpacing.sm)
            .frame(minHeight: InsightSpacing.minimumHitTarget)
            .background(background)
            .overlay(border)
            .contentShape(shape)
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(InsightMotion.resolved(InsightMotion.quick, reduceMotion: reduceMotion), value: configuration.isPressed)
    }

    @ViewBuilder private var background: some View {
        switch kind {
        case .primary: shape.fill(InsightPalette.accent)
        case .secondary: shape.fill(InsightPalette.accent.opacity(0.12))
        case .destructive: shape.fill(InsightPalette.critical)
        }
    }

    @ViewBuilder private var border: some View {
        if kind == .secondary {
            shape.strokeBorder(contrast == .increased ? InsightPalette.accent : InsightPalette.accent.opacity(0.35), lineWidth: 1)
        }
    }
}
