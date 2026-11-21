/// 時間の軸の点列と点ごとの色の分類から、地図に描く色の区間の線を作ります。
///
/// - 辺 (i→i+1) の分類は点 i の分類です。同じ分類が続く辺を1本にまとめ、境目の点は両方の線に含めます。
/// - 区間(`segmentIndex` が同じ連続した点)をまたいでつなぎません。点が1つの区間は描きません。
/// - 短い色の区間の併合(値の色分けのみ)と、色の区間ごとに端点を保った間引きを行います。
///   併合しても線の端点の合計が点数の上限を超える時は、最小の長さを倍々にして併合し直します(端点を残すと上限を守れないため)。
/// - 値による色分けも重ね合わせ(5c)も、同じ「位置の連番の範囲 → 分類」の形で受け取ります。
nonisolated struct RouteAnalysisLinePainter: Sendable {
    /// 色の区間1つ(点の位置の範囲 start...end と分類、辺の長さの合計)です。
    private typealias ColorPiece = (start: Int, end: Int, category: RouteAnalysisColorCategory, meters: Double)

    /// 最小の長さを倍々にして併合し直す回数の上限です。
    private static let maximumMergeSteps = 32

    /// 折れ線の間引きです。
    private let simplifier: GeoPolylineSimplifier
    /// 辺の長さを求める距離計算です。
    private let distance: GeoDistanceCalculator
    /// 併合する時の色の区間の最小の長さ(m。これ未満を併合)です。
    private let minimumRunMeters: Double

    /// 間引き・距離計算・最小の長さを固定して作ります。
    ///
    /// 責務: 線を作る時に使う部品と、短い区間の併合のしきい値を保持します。
    /// - Parameters:
    ///   - simplifier: 色の区間ごとの折れ線の間引き。
    ///   - distance: 辺の長さの計算。
    ///   - minimumRunMeters: これ未満の長さの色の区間を併合する(既定は 30 m。ちょうどは併合しない)。
    init(simplifier: GeoPolylineSimplifier = .init(), distance: GeoDistanceCalculator = .init(), minimumRunMeters: Double = 30) {
        self.simplifier = simplifier
        self.distance = distance
        self.minimumRunMeters = minimumRunMeters
    }

    /// 点ごとの分類から、色の区間ごとの線を作ります。
    ///
    /// 責務: 区間ごとに同じ分類の連続した辺を1本にまとめ、必要なら短い区間を併合し、点の合計を上限以下へ間引いて番号を振ります。
    /// - Parameters:
    ///   - timeline: 時刻の昇順の点列。
    ///   - categories: `timeline.points` と同じ順の点ごとの分類。足りない点は `.noValue` とみなします。
    ///   - mergesShortRuns: `true` の時だけ、最小の長さ未満の色の区間を直前(先頭なら次)へ併合します。
    ///   - pointBudget: 線の点の合計の上限(各線の端点は必ず残します)。
    ///     併合しない時は、端点の合計が上限を超えると上限を超えた点数を返します。
    /// - Returns: 0 から番号を振った線。強調はしません。
    func lines(
        timeline: RouteAnalysisTimeline,
        categories: [RouteAnalysisColorCategory],
        mergesShortRuns: Bool,
        pointBudget: Int
    ) -> [RouteAnalysisMapLine] {
        let points = timeline.points
        let segmentPieces = Self.segmentRanges(of: points).map { range in
            colorPieces(in: range, points: points, categories: categories, measures: mergesShortRuns)
        }
        let pieces = mergesShortRuns ? mergedWithinBudget(segmentPieces, pointBudget: pointBudget) : segmentPieces.flatMap { $0 }
        let simplified = simplifier.simplify(
            pieces.map { piece in points[piece.start...piece.end].map(\.coordinate) },
            pointBudget: pointBudget
        )
        return zip(pieces, simplified).enumerated().map { index, pair in
            RouteAnalysisMapLine(
                id: index,
                coordinates: pair.1,
                category: pair.0.category,
                isApproximate: points[pair.0.start].precision == .approximate,
                isEmphasized: false
            )
        }
    }

    /// 色の区間の列を連番の範囲で引き、点ごとの分類を返します。
    ///
    /// 責務: 各点の連番を含む最初の(配列の先にある)区間の分類を選び、どれにも入らない点は fallback にします。
    /// 連番の順に並べた点を区間ごとに二分探索し、分類済みの点を飛ばすので、各点に分類を書くのは1回だけです。
    /// - Parameters:
    ///   - timeline: 時刻の昇順の点列。
    ///   - runs: 位置の連番の範囲 → 分類の列(先にあるものが優先)。
    ///   - fallback: どの範囲にも入らない点の分類。
    /// - Returns: `timeline.points` と同じ順の点ごとの分類。
    func categories(
        timeline: RouteAnalysisTimeline,
        runs: [RouteAnalysisColorRun],
        fallback: RouteAnalysisColorCategory
    ) -> [RouteAnalysisColorCategory] {
        let points = timeline.points
        let order = points.indices.sorted { points[$0].sequence < points[$1].sequence }
        let sequences = order.map { points[$0].sequence }
        var assigned = [RouteAnalysisColorCategory?](repeating: nil, count: points.count)
        var nextOpen = Array(0...order.count)
        for run in runs {
            var cursor = Self.openPosition(from: Self.lowerBound(of: run.sequenceRange.lowerBound, in: sequences), in: &nextOpen)
            while cursor < order.count, sequences[cursor] <= run.sequenceRange.upperBound {
                assigned[order[cursor]] = run.category
                nextOpen[cursor] = cursor + 1
                cursor = Self.openPosition(from: cursor + 1, in: &nextOpen)
            }
        }
        return assigned.map { $0 ?? fallback }
    }

    /// 点列を、同じ区間の番号が続く位置の範囲に分けます。
    ///
    /// 責務: 隣の点と区間の番号が変わる所で区切り、2点以上の範囲だけを返します。
    /// - Parameter points: 時刻の昇順の点列。
    /// - Returns: 点の位置の半開区間の列(2点以上のものだけ)。
    private static func segmentRanges(of points: [RouteAnalysisTimelinePoint]) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var start = 0
        for index in points.indices where index == points.count - 1 || points[index + 1].segmentIndex != points[index].segmentIndex {
            if index > start { ranges.append(start..<(index + 1)) }
            start = index + 1
        }
        return ranges
    }

    /// 1つの区間の辺を、同じ分類が続く色の区間にまとめます。
    ///
    /// 責務: 辺 (i→i+1) に点 i の分類を付け、分類が変わる点で区切ります。measures が `true` の時だけ辺の長さを足し合わせます。
    /// - Parameters:
    ///   - range: 区間の点の位置(2点以上)。
    ///   - points: 時刻の昇順の点列。
    ///   - categories: 点ごとの分類。
    ///   - measures: 長さを求めるなら `true`。
    /// - Returns: 区間の中の色の区間の列(点の位置は両端を含み、境目の点を両方に含む)。
    private func colorPieces(
        in range: Range<Int>,
        points: [RouteAnalysisTimelinePoint],
        categories: [RouteAnalysisColorCategory],
        measures: Bool
    ) -> [ColorPiece] {
        var pieces: [ColorPiece] = []
        for index in range.lowerBound..<(range.upperBound - 1) {
            let category = categories.indices.contains(index) ? categories[index] : .noValue
            let meters = measures ? distance.distanceMeters(points[index].coordinate, points[index + 1].coordinate) : 0
            if let last = pieces.last, last.category == category {
                pieces[pieces.count - 1] = (last.start, index + 1, category, last.meters + meters)
            } else {
                pieces.append((index, index + 1, category, meters))
            }
        }
        return pieces
    }

    /// 区間ごとに短い色の区間を併合し、端点の合計が上限に収まるまで最小の長さを倍々にします。
    ///
    /// 責務: 最小の長さで併合し、線の端点(1本に2点)の合計が上限を超える間は、最小の長さを2倍にして併合し直します(回数に上限あり)。
    /// - Parameters:
    ///   - segmentPieces: 区間ごとの色の区間の列。
    ///   - pointBudget: 線の点の合計の上限。
    /// - Returns: 区間の順に連結した、併合後の色の区間の列。
    private func mergedWithinBudget(_ segmentPieces: [[ColorPiece]], pointBudget: Int) -> [ColorPiece] {
        var threshold = minimumRunMeters
        var current = segmentPieces.map { merged($0, minimumMeters: threshold) }
        var steps = 0
        while current.reduce(0, { $0 + $1.count * 2 }) > pointBudget, steps < Self.maximumMergeSteps, threshold > 0, threshold.isFinite {
            threshold *= 2
            steps += 1
            current = current.map { merged($0, minimumMeters: threshold) }
        }
        return current.flatMap { $0 }
    }

    /// 最小の長さ未満の色の区間を、直前(先頭なら次)の区間へ併合します。
    ///
    /// 責務: 先頭から順に、短い区間は直前の区間の分類に含め、まだ短い先頭の区間は次の区間の分類に含め、併合後に同じ分類が並べば1つにします。
    /// - Parameters:
    ///   - pieces: 1つの区間の中の色の区間の列。
    ///   - minimumMeters: これ未満の長さの区間を併合する(ちょうどは併合しない)。
    /// - Returns: 併合した色の区間の列。
    private func merged(_ pieces: [ColorPiece], minimumMeters: Double) -> [ColorPiece] {
        var result: [ColorPiece] = []
        for piece in pieces {
            guard let last = result.last else {
                result.append(piece)
                continue
            }
            let combinedMeters = last.meters + piece.meters
            if result.count == 1, last.meters < minimumMeters {
                result[0] = (last.start, piece.end, piece.category, combinedMeters)
            } else if piece.meters < minimumMeters || last.category == piece.category {
                result[result.count - 1] = (last.start, piece.end, last.category, combinedMeters)
            } else {
                result.append(piece)
            }
        }
        return result
    }

    /// 昇順の連番の列で、指定の値以上の最初の位置を返します。
    ///
    /// 責務: 二分探索で下限の位置を求めます。
    /// - Parameters:
    ///   - value: 探す連番。
    ///   - sequences: 昇順の連番の列。
    /// - Returns: 該当する最初の位置。すべて小さければ `sequences.count`。
    private static func lowerBound(of value: Int64, in sequences: [Int64]) -> Int {
        var low = 0
        var high = sequences.count
        while low < high {
            let middle = (low + high) / 2
            if sequences[middle] < value {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low
    }

    /// 指定の位置以降で、まだ分類していない最初の位置を返します。
    ///
    /// 責務: 「次の未分類の位置」の表をたどり、たどった経路を答えへ直接つなぎ替えます(各値は自分以上なので必ず止まります)。
    /// - Parameters:
    ///   - position: 探し始める位置。
    ///   - nextOpen: 位置ごとの「次の未分類の位置」。末尾の番兵は自分自身を指します。
    /// - Returns: 未分類の最初の位置。無ければ点の数。
    private static func openPosition(from position: Int, in nextOpen: inout [Int]) -> Int {
        var root = position
        while nextOpen[root] != root { root = nextOpen[root] }
        var current = position
        while current != root {
            let next = nextOpen[current]
            nextOpen[current] = root
            current = next
        }
        return root
    }
}
