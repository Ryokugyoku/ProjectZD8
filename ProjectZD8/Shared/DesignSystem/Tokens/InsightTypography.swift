import SwiftUI

/// タイポグラフィの基準値。すべて Dynamic Type に追従するテキストスタイルを土台にする。
///
/// 計測値は丸みのある数字(rounded)+等幅数字(monospacedDigit)にして、値が更新されても桁幅が揺れないようにする。
enum InsightTypography {
    /// 画面の大見出し。
    static let screenTitle = Font.system(.title, design: .default, weight: .bold)
    /// カード・セクションの見出し。
    static let sectionTitle = Font.system(.headline, design: .default, weight: .semibold)
    /// 本文。
    static let body = Font.system(.body)
    /// 補足説明・二次情報。
    static let caption = Font.system(.footnote)
    /// 小さな注記。
    static let footnote = Font.system(.caption)
    /// ラベル(指標名・キー)。
    static let label = Font.system(.footnote, design: .default, weight: .medium)
    /// バッジ内の文字。
    static let badge = Font.system(.caption, design: .rounded, weight: .semibold)
    /// ボタンのタイトル。
    static let button = Font.system(.body, design: .default, weight: .semibold)

    /// 主役となる計測値(メトリクスタイル等)。
    static let metricValueLarge = numeric(.largeTitle, weight: .semibold)
    /// 標準の計測値。
    static let metricValue = numeric(.title2, weight: .semibold)
    /// 小さめの計測値(行内・一覧)。
    static let metricValueSmall = numeric(.body, weight: .medium)
    /// 計測値の単位。
    static let metricUnit = Font.system(.callout, design: .rounded, weight: .medium)

    /// 計測値向けの丸み+等幅数字フォント。
    ///
    /// 責務: 指定スタイルの rounded フォントに monospacedDigit を適用して返す。
    static func numeric(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        Font.system(style, design: .rounded, weight: weight).monospacedDigit()
    }
}
