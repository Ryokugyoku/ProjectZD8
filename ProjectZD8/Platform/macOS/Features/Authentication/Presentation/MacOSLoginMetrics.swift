#if os(macOS)
import CoreGraphics

/// macOSログイン画面のウインドウ寸法に応じた表示規則です。
struct MacOSLoginMetrics: Equatable {
    /// ログイン画面全体の構成です。
    enum Layout: Equatable {
        /// ブランド領域と認証パネルを縦一列に並べる構成です。
        case singleColumn

        /// 左にブランド領域、右に認証パネルを置く二列構成です。
        case split
    }

    /// 画面全体の構成です。
    let layout: Layout

    /// 基準ウインドウに対する内部コンテンツ倍率です。
    let scale: CGFloat

    /// 画面外周の余白です。
    let outerPadding: CGFloat

    /// 二列構成での列間隔です。
    let columnSpacing: CGFloat

    /// ブランド領域(一列構成では全コンテンツ)の最大幅です。
    let contentMaxWidth: CGFloat

    /// 認証パネルの幅(一列構成では最大幅)です。
    let panelWidth: CGFloat

    /// コックピット意匠の直径です。
    let heroDiameter: CGFloat

    /// コックピット意匠を見出しの横へ置くかどうかです。
    let placesHeroBesideIntroduction: Bool

    /// 横並びを縦積みへ切り替えるかどうかです。
    var usesStackedLayout: Bool {
        layout == .singleColumn
    }

    /// 利用可能ウインドウ寸法と文字拡大状態からmacOS専用表示規則を解決します。
    ///
    /// 責務: 1件のmacOS表示領域を最小ウインドウでも操作可能なログイン寸法へ変換します。
    /// - Parameters:
    ///   - size: ウインドウ内で利用可能な表示領域。
    ///   - usesAccessibilityText: アクセシビリティ文字サイズを使用しているかどうか。
    /// - Returns: macOSログイン画面のレスポンシブ表示規則。
    static func resolve(size: CGSize, usesAccessibilityText: Bool) -> MacOSLoginMetrics {
        let scale = clamp(min(size.width / 1200, size.height / 800), lower: 0.82, upper: 1.35)
        let outerPadding = max(20, 36 * scale)
        let usesSplit = size.width >= 860 && size.height >= 520 && !usesAccessibilityText

        if usesSplit {
            let panelWidth = clamp(size.width * 0.34, lower: 360, upper: 460)
            let columnSpacing = max(32, 56 * scale)
            let showcaseWidth = size.width - (outerPadding * 2) - panelWidth - columnSpacing
            let heroBeside = showcaseWidth >= 600 && size.height >= 620
            let heroDiameter = heroBeside
                ? clamp(min(showcaseWidth * 0.4, size.height * 0.42), lower: 160, upper: 340)
                : clamp(min(showcaseWidth * 0.5, size.height * 0.3), lower: 120, upper: 240)
            return MacOSLoginMetrics(
                layout: .split,
                scale: scale,
                outerPadding: outerPadding,
                columnSpacing: columnSpacing,
                contentMaxWidth: min(showcaseWidth, 820),
                panelWidth: panelWidth,
                heroDiameter: heroDiameter,
                placesHeroBesideIntroduction: heroBeside
            )
        }

        let contentWidth = min(max(size.width - (outerPadding * 2), 360), 600)
        return MacOSLoginMetrics(
            layout: .singleColumn,
            scale: scale,
            outerPadding: outerPadding,
            columnSpacing: 0,
            contentMaxWidth: contentWidth,
            panelWidth: contentWidth,
            heroDiameter: clamp(min(contentWidth * 0.36, size.height * 0.3), lower: 110, upper: 200),
            placesHeroBesideIntroduction: contentWidth >= 520 && !usesAccessibilityText
        )
    }

    /// 値を下限と上限の間へ収めます。
    ///
    /// 責務: 1件の寸法候補を表示可能範囲へ制限します。
    /// - Parameters:
    ///   - value: 制限前の寸法。
    ///   - lower: 許容する最小寸法。
    ///   - upper: 許容する最大寸法。
    /// - Returns: 範囲内へ収めた寸法。
    private static func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        min(max(value, lower), upper)
    }
}
#endif
