import Foundation

/// グラフで選んだ時刻と、その時刻の位置・値の読み出しです。
nonisolated struct RouteAnalysisCursor: Equatable, Sendable {
    /// 選んだ時刻です。
    let date: Date
    /// その時刻の位置です。許容差の中に位置が無い時は `nil` です。
    let coordinate: GeoCoordinate?
    /// その時刻の指標の値の文字列です。値が無い時は `nil` です。
    let metricValueText: String?
    /// その時刻の標高の文字列です。標高が無い時は `nil` です。
    let elevationText: String?
}
