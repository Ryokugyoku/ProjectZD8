import Foundation

/// 強調する時刻の範囲を、地図の上に重ねる強調の線へ変換します。
///
/// - 範囲ごとに、時刻が範囲に入る(両端を含む)点を集め、区間(`segmentIndex`)が同じ連続した点を1本の線にします。
/// - 区間をまたいでつながず、点が1つだけの部分は線にしません。
/// - 線の分類は基本の色(`.base`)、`isEmphasized` は `true` です。間引きはしません(点数の上限は呼び出し側が守ります)。
nonisolated struct RouteAnalysisHighlightBuilder: Sendable {
    /// 時刻の範囲ごとの強調の線を作ります。
    ///
    /// 責務: 範囲の順に、範囲に入る点を区間ごとの線にまとめ、firstID から番号を振ります。
    /// - Parameters:
    ///   - timeline: 時刻の昇順の点列。
    ///   - ranges: 強調する時刻の範囲(両端を含む)。
    ///   - firstID: 最初の線に振る番号。
    /// - Returns: 強調の線(範囲の順、範囲の中では時刻の順)。
    func lines(timeline: RouteAnalysisTimeline, ranges: [ClosedRange<Date>], firstID: Int) -> [RouteAnalysisMapLine] {
        let points = timeline.points
        let pieces = ranges.flatMap { Self.segmentPieces(in: Self.positions(of: $0, in: points), points: points) }
        return pieces.enumerated().map { offset, piece in
            RouteAnalysisMapLine(
                id: firstID + offset,
                coordinates: points[piece].map(\.coordinate),
                category: .base,
                isApproximate: points[piece.lowerBound].precision == .approximate,
                isEmphasized: true
            )
        }
    }

    /// 時刻が範囲に入る点の位置の範囲を返します。
    ///
    /// 責務: 時刻の昇順を前提に、範囲の下端以降の最初の点から、上端を超える手前までを求めます。
    /// - Parameters:
    ///   - range: 時刻の範囲(両端を含む)。
    ///   - points: 時刻の昇順の点列。
    /// - Returns: 点の位置の半開区間(空のこともある)。
    private static func positions(of range: ClosedRange<Date>, in points: [RouteAnalysisTimelinePoint]) -> Range<Int> {
        let start = firstIndex(in: points) { $0.date >= range.lowerBound }
        let end = firstIndex(in: points) { $0.date > range.upperBound }
        return start..<max(start, end)
    }

    /// 位置の範囲を、区間の番号が同じ連続した部分に分けます。
    ///
    /// 責務: 隣の点と区間の番号が変わる所で区切り、2点以上の部分だけを返します。
    /// - Parameters:
    ///   - range: 点の位置の範囲。
    ///   - points: 時刻の昇順の点列。
    /// - Returns: 2点以上の部分の位置の範囲。
    private static func segmentPieces(in range: Range<Int>, points: [RouteAnalysisTimelinePoint]) -> [Range<Int>] {
        var pieces: [Range<Int>] = []
        var start = range.lowerBound
        for index in range where index == range.upperBound - 1 || points[index + 1].segmentIndex != points[index].segmentIndex {
            if index > start { pieces.append(start..<(index + 1)) }
            start = index + 1
        }
        return pieces
    }

    /// 条件を満たす最初の点の位置を返します。
    ///
    /// 責務: 条件が時刻の昇順に対して単調(偽の後に真が続く)である前提で二分探索します。
    /// - Parameters:
    ///   - points: 時刻の昇順の点列。
    ///   - isAtOrAfter: 点が境界以降なら `true` を返す条件。
    /// - Returns: 条件を満たす最初の位置。無ければ点の数。
    private static func firstIndex(
        in points: [RouteAnalysisTimelinePoint],
        where isAtOrAfter: (RouteAnalysisTimelinePoint) -> Bool
    ) -> Int {
        var low = 0
        var high = points.count
        while low < high {
            let middle = (low + high) / 2
            if isAtOrAfter(points[middle]) {
                high = middle
            } else {
                low = middle + 1
            }
        }
        return low
    }
}
