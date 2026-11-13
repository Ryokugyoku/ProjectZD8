import CoreGraphics
import Foundation

/// スパークラインの欠損対応セグメント分割を行う純粋ロジック。
nonisolated enum SparklineGeometry {
    /// 欠損(nil / 非有限値)を境に分割した連続区間の点列。
    struct Segment: Equatable {
        /// 区間内の点(x 昇順)。
        var points: [CGPoint]
    }

    /// 値の描画レンジを決める。
    ///
    /// 責務: 明示レンジがあればそれ、なければ有限値の最小・最大(同値なら±0.5 に広げる)を返す。有限値が無ければ nil。
    static func resolvedRange(values: [Double?], explicit: ClosedRange<Double>?) -> ClosedRange<Double>? {
        if let explicit, explicit.upperBound > explicit.lowerBound { return explicit }
        let finite = values.compactMap { $0 }.filter(\.isFinite)
        guard let low = finite.min(), let high = finite.max() else { return nil }
        return low == high ? (low - 0.5)...(high + 0.5) : low...high
    }

    /// 値列を欠損で区切った点列へ変換する。
    ///
    /// 責務: nil / 非有限値を隙間として保ち、各有限値を size 内の座標(上が大きい値)へ写像した連続区間に分ける。
    static func segments(values: [Double?], range: ClosedRange<Double>, size: CGSize) -> [Segment] {
        guard !values.isEmpty, range.upperBound > range.lowerBound, size.width > 0, size.height > 0 else { return [] }
        let span = range.upperBound - range.lowerBound
        let stepX = values.count > 1 ? size.width / CGFloat(values.count - 1) : 0
        var result: [Segment] = []
        var current: [CGPoint] = []
        for (index, raw) in values.enumerated() {
            guard let value = raw, value.isFinite else {
                if !current.isEmpty { result.append(Segment(points: current)); current = [] }
                continue
            }
            let clamped = min(1, max(0, (value - range.lowerBound) / span))
            let x = values.count > 1 ? stepX * CGFloat(index) : size.width / 2
            current.append(CGPoint(x: x, y: size.height * (1 - CGFloat(clamped))))
        }
        if !current.isEmpty { result.append(Segment(points: current)) }
        return result
    }
}
