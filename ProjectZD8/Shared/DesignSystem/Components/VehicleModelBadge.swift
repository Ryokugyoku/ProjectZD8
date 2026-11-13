import SwiftUI

/// 車種専用データの適用型式を円形アクセントで表示します。
struct VehicleModelBadge: View {
    /// 表示する車両型式です。
    let modelCode: String

    /// 型式文字列を円形の専用PID識別表示として描画します。
    ///
    /// 責務: 1件の型式文字列をiOSとmacOSで共通する円形バッジへ変換します。
    var body: some View {
        Text(modelCode)
            .font(.system(size: 9, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .minimumScaleFactor(0.7)
            .lineLimit(1)
            .frame(width: 38, height: 38)
            .background(
                Circle().fill(
                    LinearGradient(
                        colors: [.indigo, .blue, .cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            )
            .overlay { Circle().stroke(.white.opacity(0.7), lineWidth: 1.5) }
            .shadow(color: .blue.opacity(0.28), radius: 7, y: 3)
            .accessibilityLabel(Text("vehicle_specific_pid.badge \(modelCode)"))
    }
}
