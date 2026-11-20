import SwiftUI

/// 地図に描く線1本の見た目(色・太さ・破線か)です。機能の知識を持たない汎用の値です。
struct RouteMapLineAppearance: Equatable {
    /// 線の色です。
    let color: Color
    /// 線の太さ(pt)です。
    let width: CGFloat
    /// 破線で描く時に `true` です。
    let isDashed: Bool
}
