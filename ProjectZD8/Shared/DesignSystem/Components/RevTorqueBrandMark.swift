import SwiftUI

/// RevTorque Insightのアプリアイコン風ブランドタイルです。
struct RevTorqueBrandMark: View {
    /// タイルの一辺の長さです。
    let size: CGFloat

    /// 指定サイズでブランドタイルを生成します。
    ///
    /// 責務: 1件のブランドタイルへ表示寸法を固定します。
    /// - Parameter size: タイルの一辺の長さ。
    init(size: CGFloat) {
        self.size = size
    }

    /// 深いネイビーのタイルへ計器シンボルとピーク強調点を描画します。
    ///
    /// 責務: 製品名の隣に置く装飾ブランドタイルを描画します。
    var body: some View {
        let cornerRadius = size * 0.27
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.015, green: 0.075, blue: 0.14),
                            Color(red: 0.025, green: 0.15, blue: 0.23)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: "gauge.with.dots.needle.50percent")
                .font(.system(size: size * 0.47, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Circle()
                .fill(.orange)
                .frame(width: size * 0.1, height: size * 0.1)
                .offset(x: size * 0.25, y: -size * 0.23)
        }
        .frame(width: size, height: size)
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.accentColor.opacity(0.32), lineWidth: 1)
        }
        .shadow(color: Color.accentColor.opacity(0.3), radius: size * 0.28, y: size * 0.12)
        .accessibilityHidden(true)
    }
}
