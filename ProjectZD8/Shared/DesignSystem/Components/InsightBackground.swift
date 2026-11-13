import SwiftUI

/// 画面全体の控えめな適応型背景。システム背景色に、上部のごく淡いアクセントの光を重ねる。
///
/// コントラスト増加時は光を消して単色にする。
struct InsightBackground: View {
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme

    /// 背景を作る。
    ///
    /// 責務: 環境に応じた背景を描く。
    init() {}

    var body: some View {
        ZStack {
            Rectangle().fill(.background)
            if contrast != .increased {
                RadialGradient(
                    colors: [InsightPalette.accent.opacity(colorScheme == .dark ? 0.16 : 0.08), .clear],
                    center: .top,
                    startRadius: 0,
                    endRadius: 520
                )
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

#Preview("Light") {
    InsightBackground().preferredColorScheme(.light)
}

#Preview("Dark") {
    InsightBackground().preferredColorScheme(.dark)
}
