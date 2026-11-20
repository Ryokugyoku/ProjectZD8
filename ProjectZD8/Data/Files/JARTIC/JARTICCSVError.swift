import Foundation

/// JARTIC の CSV を行と項目に区切る時の失敗です。
///
/// どちらも取り込み全体を止めます(壊れた入力を途中まで取り込んだ成功にしません)。
nonisolated enum JARTICCSVError: Error, Equatable, Sendable {
    /// 1行の長さが上限(既定 4 MiB)を超えました。1項目の長さも、この上限で抑えます。
    case rowTooLong
    /// 引用符の途中でファイルが終わりました。
    case unterminatedQuote
}
