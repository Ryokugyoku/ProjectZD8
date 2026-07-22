import SwiftUI

/// 警告文やカードを動かさず三角アイコンだけへ短い注意振動を加えます。
struct WarningTriangleIcon: View {
    /// SF Symbolの表示寸法です。
    let size: CGFloat
    /// 警告アイコンの表示色です。
    let color: Color
    /// 短い振動を開始する進行値です。
    @State private var shakeProgress: CGFloat = 0
    /// ユーザーが動きを減らす設定を有効にしているかを示します。
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    /// 表示寸法と色を固定して生成します。
    ///
    /// 責務: 1件の警告三角表示へ寸法と色を固定します。
    /// - Parameters:
    ///   - size: SF Symbolの表示寸法。
    ///   - color: 警告アイコンの表示色。
    init(size: CGFloat, color: Color = .orange) {
        self.size = size
        self.color = color
    }

    /// Reduce Motionを尊重する警告三角を描画します。
    ///
    /// 責務: 警告三角アイコンだけを1秒間隔の短い横振動へ変換します。
    var body: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(color)
            .modifier(AttentionShakeEffect(
                progress: accessibilityReduceMotion ? 0 : shakeProgress,
                amplitude: 3
            ))
            .accessibilityHidden(true)
            .task(id: accessibilityReduceMotion) {
                guard !accessibilityReduceMotion else {
                    shakeProgress = 0
                    return
                }
                while !Task.isCancelled {
                    withAnimation(.linear(duration: 0.55)) {
                        shakeProgress += 1
                    }
                    try? await Task.sleep(for: .seconds(1))
                }
            }
    }
}
