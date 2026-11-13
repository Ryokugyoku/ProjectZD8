#if os(iOS)
import CoreGraphics

/// iOSログイン画面の利用可能サイズに応じた表示寸法です。
struct IOSLoginMetrics: Equatable {
    /// ログイン画面全体の構成です。
    enum Layout: Equatable {
        /// ブランド領域と認証操作を縦一列に並べる構成です。
        case singleColumn

        /// 左にブランド領域、右に認証パネルを置く二列構成です。
        case split
    }

    /// 画面全体の構成です。
    let layout: Layout

    /// 一列構成で認証操作を画面下部へ固定するかどうかです。iPhone幅のみ固定します。
    let docksAuthenticationPanel: Bool

    /// コンテンツ左右の余白です。
    let horizontalPadding: CGFloat

    /// ブランド領域(一列構成では全コンテンツ)の最大幅です。
    let contentMaxWidth: CGFloat

    /// 二列構成での認証パネル幅です。
    let panelWidth: CGFloat

    /// 二列構成での列間隔です。
    let columnSpacing: CGFloat

    /// コックピット意匠の直径です。
    let heroDiameter: CGFloat

    /// 縦方向の主要要素間隔です。
    let sectionSpacing: CGFloat

    /// 製品特性タイルを横に並べる列数です。
    let capabilityColumnCount: Int

    /// 見出しを大型表示にするかどうかです。
    let usesDisplayTitle: Bool

    /// 高さが限られた端末向けのコンパクト構成かどうかです。
    let usesCompactHeight: Bool

    /// 利用可能サイズと文字拡大状態からiOS専用寸法を解決します。
    ///
    /// 責務: 1件のiOS表示領域を見切れず操作し続けられるログイン画面寸法へ変換します。
    /// - Parameters:
    ///   - size: Safe Area内で利用可能な表示領域。
    ///   - usesAccessibilityText: アクセシビリティ文字サイズを使用しているかどうか。
    /// - Returns: iPhoneとiPadで使用するレスポンシブ表示寸法。
    static func resolve(size: CGSize, usesAccessibilityText: Bool) -> IOSLoginMetrics {
        let compactHeight = size.height < 700 || usesAccessibilityText
        let isLandscapeLike = size.width >= size.height * 0.9
        let usesSplit = size.width >= 560
            && isLandscapeLike
            && !(usesAccessibilityText && size.width < 900)
        let horizontalPadding: CGFloat = if size.width < 360 {
            18
        } else if size.width >= 700 && size.height >= 500 {
            40
        } else {
            24
        }
        let capabilityColumns = usesAccessibilityText ? 1 : 3

        if usesSplit {
            let panelWidth = clamp(size.width * 0.38, lower: 320, upper: 440)
            let columnSpacing: CGFloat = size.width >= 1000 ? 64 : 28
            let showcaseWidth = max(size.width - (horizontalPadding * 2) - panelWidth - columnSpacing, 220)
            return IOSLoginMetrics(
                layout: .split,
                docksAuthenticationPanel: false,
                horizontalPadding: horizontalPadding,
                contentMaxWidth: min(showcaseWidth, 620),
                panelWidth: panelWidth,
                columnSpacing: columnSpacing,
                heroDiameter: clamp(min(showcaseWidth * 0.55, size.height * 0.4), lower: 112, upper: 300),
                sectionSpacing: compactHeight ? 16 : 26,
                capabilityColumnCount: capabilityColumns,
                usesDisplayTitle: size.width >= 1000 && !usesAccessibilityText,
                usesCompactHeight: compactHeight
            )
        }

        let contentWidth = min(max(size.width - (horizontalPadding * 2), 280), 560)
        return IOSLoginMetrics(
            layout: .singleColumn,
            docksAuthenticationPanel: !usesAccessibilityText && size.width < 600,
            horizontalPadding: horizontalPadding,
            contentMaxWidth: contentWidth,
            panelWidth: contentWidth,
            columnSpacing: 0,
            heroDiameter: clamp(
                min(contentWidth * 0.62, size.height * (compactHeight ? 0.24 : 0.3)),
                lower: 112,
                upper: 280
            ),
            sectionSpacing: compactHeight ? 18 : 26,
            capabilityColumnCount: capabilityColumns,
            usesDisplayTitle: false,
            usesCompactHeight: compactHeight
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
