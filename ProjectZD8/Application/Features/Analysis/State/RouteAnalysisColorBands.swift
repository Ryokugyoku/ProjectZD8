/// 値を色の段へ分ける固定の境界です。下限を含み上限を含まず、境界ちょうどの値は上の区分です。
nonisolated struct RouteAnalysisColorBands: Equatable, Sendable {
    /// 区分の境界(有限で狭義の昇順、1つ以上)です。
    let boundaries: [Double]

    /// 境界を検査して区分を作ります。
    ///
    /// 責務: 1つ以上の有限な値が狭義の昇順に並ぶ境界だけを受け入れます。
    /// - Parameter boundaries: 区分の境界。
    /// - Returns: 空、有限でない値を含む、または狭義の昇順でない時は `nil`。
    init?(boundaries: [Double]) {
        guard !boundaries.isEmpty,
              boundaries.allSatisfy(\.isFinite),
              zip(boundaries, boundaries.dropFirst()).allSatisfy({ $0 < $1 })
        else { return nil }
        self.boundaries = boundaries
    }

    /// 区分の数(境界の数 + 1)です。
    var stepCount: Int {
        boundaries.count + 1
    }

    /// 値が入る区分の番号を返します。
    ///
    /// 責務: 値以下の境界の数を区分の番号(0 始まり)として返します。
    /// - Parameter value: 区分を調べる値。
    /// - Returns: 区分の番号(0...stepCount-1)。値が有限でなければ `nil`。
    func step(for value: Double) -> Int? {
        guard value.isFinite else { return nil }
        return boundaries.firstIndex(where: { value < $0 }) ?? boundaries.count
    }
}
