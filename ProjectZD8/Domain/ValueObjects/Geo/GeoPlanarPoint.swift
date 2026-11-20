import Foundation

/// 局所的な平面へ投影した点です。東が +x、北が +y で、単位はメートルです。
nonisolated struct GeoPlanarPoint: Equatable, Sendable {
    /// 原点から東向きの距離(m)。
    let x: Double
    /// 原点から北向きの距離(m)。
    let y: Double
}
