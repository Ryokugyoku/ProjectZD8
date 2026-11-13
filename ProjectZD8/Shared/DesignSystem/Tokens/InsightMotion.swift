import SwiftUI

/// アニメーションの基準値。Reduce Motion が有効な場合は `InsightMotion` 経由で動きを無効化する。
enum InsightMotion {
    /// 標準の状態遷移。
    static let standard = Animation.smooth(duration: 0.3)
    /// ゲージ針・メーター充填の追従。
    static let gauge = Animation.smooth(duration: 0.45)
    /// 速い反応(選択・押下)。
    static let quick = Animation.easeOut(duration: 0.15)

    /// Reduce Motion を考慮したアニメーションを返す。
    ///
    /// 責務: Reduce Motion 有効時は nil(動きなし)、無効時は与えたアニメーションを返す。
    static func resolved(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}

private struct InsightAnimationModifier<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: Value

    func body(content: Content) -> some View {
        content.animation(InsightMotion.resolved(animation, reduceMotion: reduceMotion), value: value)
    }
}

extension View {
    /// Reduce Motion を尊重して値の変化をアニメーションする。
    ///
    /// 責務: 環境の Reduce Motion を読み、有効なら動かさずに値変化へ追従させる。
    func insightAnimation<Value: Equatable>(_ animation: Animation = InsightMotion.standard, value: Value) -> some View {
        modifier(InsightAnimationModifier(animation: animation, value: value))
    }
}
