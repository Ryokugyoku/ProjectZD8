import SwiftUI

/// 意味(ロール)で名前付けした色。ライト/ダーク/コントラスト増加はシステム色とアセットに任せる。
///
/// アクセントはシアン(`AccentColor` アセット)。オレンジ(`warning`)は警告・ピークの小さな強調にだけ使う。
enum InsightPalette {
    // MARK: - セマンティック

    /// ブランドのアクセント(シアン)。
    static let accent = Color.accentColor
    /// 正常・成功。
    static let positive = Color.green
    /// 警告・ピーク。小さな強調にのみ使う。
    static let warning = Color.orange
    /// 異常・失敗。
    static let critical = Color.red
    /// 中立(無効・待機)。
    static let neutral = Color.secondary

    // MARK: - 面と線(背景に重ねる半透明。ライト/ダークで自動反転する primary を土台にする)

    /// カードなど内容を載せる面。
    static let surface = Color.primary.opacity(0.05)
    /// 面の上にさらに載せる面・タイルの背景。
    static let surfaceRaised = Color.primary.opacity(0.08)
    /// 区切り線・カードの縁。
    static let stroke = Color.primary.opacity(0.10)
    /// コントラスト増加時の縁。
    static let strokeStrong = Color.primary.opacity(0.35)
    /// ゲージ・メーターの未充填トラック。
    static let track = Color.primary.opacity(0.12)

    // MARK: - チャート

    /// チャート系列色。先頭がアクセント。オレンジは警告専用のため含めない。
    static let chartSeries: [Color] = [
        Color.accentColor, .indigo, .mint, .purple, .pink, .yellow, .teal, .brown
    ]

    /// 系列インデックスに対応する色。範囲外は循環する。
    ///
    /// 責務: 任意の整数インデックスを `chartSeries` の色へ割り当てる。
    static func series(_ index: Int) -> Color {
        let count = chartSeries.count
        return chartSeries[((index % count) + count) % count]
    }

    /// 縁の色。コントラスト増加を考慮する。
    ///
    /// 責務: 環境のコントラスト設定に応じた縁色を返す。
    static func border(for contrast: ColorSchemeContrast) -> Color {
        contrast == .increased ? strokeStrong : stroke
    }
}
