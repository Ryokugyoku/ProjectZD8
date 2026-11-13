import SwiftUI

/// 注目対象へ短い横振動を適用する小さな視覚効果です。
struct AttentionShakeEffect: GeometryEffect {
    /// 振動アニメーションの0から1までの進行値です。
    var progress: CGFloat

    /// 振動の最大水平移動量です。
    let amplitude: CGFloat

    /// SwiftUIが補間する振動進行値です。
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    /// 現在の進行値に対応する水平振動変換を返します。
    ///
    /// 責務: 1件のアニメーション進行値を短い水平振動へ変換します。
    /// - Parameter size: 効果対象Viewの現在サイズ。
    /// - Returns: 現在フレームへ適用する水平移動変換。
    func effectValue(size: CGSize) -> ProjectionTransform {
        let translation = sin(progress * .pi * 8) * amplitude
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}
