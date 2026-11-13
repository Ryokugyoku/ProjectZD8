import SwiftUI

/// 夜間の車載コックピットを想起させる、表示領域に追従する背景です。
struct CockpitBackdrop: View {
    /// 背景の発光と格子を描画します。
    ///
    /// 責務: 表示領域の大きさに比例したグラデーション背景を描画します。
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let longSide = max(size.width, size.height)
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.055, green: 0.058, blue: 0.07),
                        Color(red: 0.025, green: 0.035, blue: 0.055),
                        Color(red: 0.016, green: 0.018, blue: 0.026)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                horizonGrid
                Circle()
                    .fill(Color.accentColor.opacity(0.17))
                    .frame(width: longSide * 0.7, height: longSide * 0.7)
                    .blur(radius: longSide * 0.14)
                    .position(x: size.width * 0.9, y: size.height * 0.05)
                Circle()
                    .fill(Color.orange.opacity(0.05))
                    .frame(width: longSide * 0.55, height: longSide * 0.55)
                    .blur(radius: longSide * 0.16)
                    .position(x: size.width * 0.05, y: size.height * 0.98)
            }
            .frame(width: size.width, height: size.height)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    /// 表示領域へ均等間隔で薄く描く、下方向へ強まる装飾格子です。
    private var horizonGrid: some View {
        Canvas { context, canvasSize in
            let spacing: CGFloat = 44
            var path = Path()
            var x: CGFloat = 0
            while x <= canvasSize.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: canvasSize.height))
                x += spacing
            }
            var y: CGFloat = 0
            while y <= canvasSize.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: canvasSize.width, y: y))
                y += spacing
            }
            context.stroke(path, with: .color(.white.opacity(0.035)), lineWidth: 0.5)
        }
        .mask(
            LinearGradient(colors: [.clear, .white], startPoint: .top, endPoint: .bottom)
        )
    }
}
