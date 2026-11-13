import SwiftUI

/// RevTorque Insightのコックピットコンセプトを表す装飾用タコメーター意匠です。
///
/// 実際の車両状態は表示せず、ログイン画面などのブランド領域でのみ使用します。
struct CockpitGaugeEmblem: View {
    /// 意匠全体の直径です。
    let diameter: CGFloat

    /// 計器の目盛りが描かれる円弧の角度幅です。
    private static let sweepDegrees: Double = 270

    /// 目盛りの総区間数です。
    private static let tickCount = 40

    /// レッドゾーンが始まる目盛り位置の割合です。
    private static let redlineFraction: Double = 0.85

    /// シアンの進捗円弧が到達する割合です。
    private static let activeFraction: Double = 0.64

    /// 指定直径で意匠を生成します。
    ///
    /// 責務: 1件の装飾計器へ表示直径を固定します。
    /// - Parameter diameter: 意匠全体の直径。
    init(diameter: CGFloat) {
        self.diameter = diameter
    }

    /// 目盛り、進捗円弧、ブランドグリフを重ねた計器意匠を描画します。
    ///
    /// 責務: 運用状態を持たない静的なタコメーター意匠を描画します。
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.accentColor.opacity(0.14), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: diameter * 0.5
                    )
                )
            sweepArc(fraction: 1)
                .stroke(.white.opacity(0.07), style: StrokeStyle(lineWidth: diameter * 0.055, lineCap: .round))
            sweepArc(fraction: Self.activeFraction)
                .stroke(
                    AngularGradient(
                        colors: [Color.accentColor.opacity(0.15), Color.accentColor, .cyan],
                        center: .center,
                        startAngle: .degrees(135),
                        endAngle: .degrees(135 + Self.sweepDegrees * Self.activeFraction)
                    ),
                    style: StrokeStyle(lineWidth: diameter * 0.022, lineCap: .round)
                )
                .shadow(color: Color.accentColor.opacity(0.55), radius: diameter * 0.03)
            tickMarks
            Circle()
                .stroke(.white.opacity(0.14), style: StrokeStyle(lineWidth: 1, dash: [2, 7]))
                .padding(diameter * 0.24)
            HStack(spacing: -diameter * 0.03) {
                Text(verbatim: "R")
                    .font(.system(size: diameter * 0.27, weight: .bold, design: .rounded))
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: diameter * 0.2, weight: .semibold))
            }
            .foregroundStyle(Color.accentColor)
            .shadow(color: Color.accentColor.opacity(0.35), radius: diameter * 0.04)
            peakMarker
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }

    /// 目盛りとレッドゾーンを描くキャンバスです。
    private var tickMarks: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let outerRadius = size.width * 0.405
            for index in 0...Self.tickCount {
                let fraction = Double(index) / Double(Self.tickCount)
                let isMajor = index.isMultiple(of: 5)
                let angle = Angle.degrees(135 + Self.sweepDegrees * fraction).radians
                let length = size.width * (isMajor ? 0.06 : 0.032)
                let start = CGPoint(
                    x: center.x + cos(angle) * (outerRadius - length),
                    y: center.y + sin(angle) * (outerRadius - length)
                )
                let end = CGPoint(
                    x: center.x + cos(angle) * outerRadius,
                    y: center.y + sin(angle) * outerRadius
                )
                var path = Path()
                path.move(to: start)
                path.addLine(to: end)
                let color: Color = fraction >= Self.redlineFraction
                    ? .orange.opacity(isMajor ? 0.9 : 0.6)
                    : .white.opacity(isMajor ? 0.55 : 0.2)
                context.stroke(
                    path,
                    with: .color(color),
                    style: StrokeStyle(lineWidth: max(1, size.width * (isMajor ? 0.011 : 0.006)), lineCap: .round)
                )
            }
        }
    }

    /// 進捗円弧の終端に置く小さなピーク強調点です。
    private var peakMarker: some View {
        let angle = Angle.degrees(135 + Self.sweepDegrees * Self.activeFraction).radians
        let radius = diameter * 0.5 - diameter * 0.0275
        return Circle()
            .fill(.white)
            .frame(width: diameter * 0.035, height: diameter * 0.035)
            .shadow(color: .cyan.opacity(0.9), radius: diameter * 0.025)
            .offset(x: cos(angle) * radius, y: sin(angle) * radius)
    }

    /// 計器の開始角から指定割合までの円弧形状を返します。
    ///
    /// 責務: 270度の計器レンジの一部を描画可能な円弧形状へ変換します。
    /// - Parameter fraction: 計器レンジに対する描画割合。
    /// - Returns: 計器開始角から回転済みの円弧形状。
    private func sweepArc(fraction: Double) -> some Shape {
        Circle()
            .inset(by: diameter * 0.0275)
            .trim(from: 0, to: Self.sweepDegrees / 360 * fraction)
            .rotation(.degrees(135))
    }
}

#Preview {
    CockpitGaugeEmblem(diameter: 240)
        .padding(40)
        .background(Color.black)
}
