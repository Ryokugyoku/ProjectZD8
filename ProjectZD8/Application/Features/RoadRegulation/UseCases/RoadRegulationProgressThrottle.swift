import Foundation

/// 取り込みの進捗の通知を間引く型です。
///
/// 通知するのは次の時だけです(画面の更新が多すぎないようにするため)。
/// - 最初の通知と、段階の種類が変わった時。
/// - 同じ段階で、全体の進み具合(`RoadRegulationImportProgressFraction`)が、最後に通知した値から `minimumFractionStep` 以上進んだ時。
/// - 同じ段階で進み具合が分からない時(ダウンロードの予定バイトが無い時など)は、最後に通知した値と違う時。
///
/// 同じ値の進捗と、進み具合が戻った進捗は通知しません。
nonisolated struct RoadRegulationProgressThrottle: Sendable {
    /// 同じ段階で通知に必要な、全体の進み具合の増分。
    private let minimumFractionStep: Double
    /// 進み具合の計算器。
    private let fractions = RoadRegulationImportProgressFraction()
    /// 最後に通知した段階。
    private var lastEmittedPhase: RoadRegulationImportPhase?

    /// 通知に必要な増分を決めます。
    ///
    /// 責務: 間引きの設定を保持します(負や有限でない値は 0 とみなします)。
    /// - Parameter minimumFractionStep: 同じ段階で通知に必要な、全体の進み具合の増分。既定 0.01(1%)。
    init(minimumFractionStep: Double = 0.01) {
        self.minimumFractionStep = minimumFractionStep.isFinite ? max(0, minimumFractionStep) : 0
    }

    /// 段階を通知するかを決め、通知するならその段階を覚えます。
    ///
    /// 責務: 段階の変化と進み具合の増分から、通知の要否を判定します。
    /// - Parameter phase: 新しい段階。
    /// - Returns: 通知するなら `true`。
    mutating func shouldEmit(_ phase: RoadRegulationImportPhase) -> Bool {
        guard isWorthEmitting(phase) else { return false }
        lastEmittedPhase = phase
        return true
    }

    /// 最後に通知した段階と比べて、通知に値するかを判定します。
    ///
    /// 責務: 段階の種類・同じ値・進み具合の増分を順に比べます。
    /// - Parameter phase: 新しい段階。
    /// - Returns: 通知に値するなら `true`。
    private func isWorthEmitting(_ phase: RoadRegulationImportPhase) -> Bool {
        guard let last = lastEmittedPhase, fractions.stage(of: last) == fractions.stage(of: phase) else { return true }
        guard phase != last else { return false }
        guard let fraction = fractions.fraction(of: phase), let lastFraction = fractions.fraction(of: last) else { return true }
        return fraction - lastFraction >= minimumFractionStep - Self.comparisonTolerance
    }

    /// 浮動小数の誤差で、ちょうどの増分を取りこぼさないための許容幅。
    private static let comparisonTolerance = 1e-9
}
