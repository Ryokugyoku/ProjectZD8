import Foundation
@testable import ProjectZD8

/// 解析の表示ロジックのテストが共有する、PID系列・相関・セッションの組み立て補助です。
enum TestSessionLogAnalysisFixtures {
    /// 指定のService/PIDを持つPID系列を作ります。
    ///
    /// 責務: 統計値と名称キーを指定できる最小のPID系列を返します。
    /// - Parameters:
    ///   - service: OBD Service番号。
    ///   - pid: PID番号。
    ///   - nameKey: 表示名キー。
    ///   - unit: 単位。
    /// - Returns: 検証用のPID系列。
    static func makeSeries(service: UInt8, pid: UInt8, nameKey: String? = nil, unit: String = "u") -> SessionPIDSeries {
        SessionPIDSeries(
            id: OBDPIDRequest(service: service, pid: pid),
            nameKey: nameKey,
            unit: unit,
            vehicleModelCode: nil,
            totalPointCount: 0,
            minimumValue: 2.2,
            averageValue: 3.3,
            maximumValue: 4.4,
            latestValue: 1.1,
            interpretationKey: "analysis.trend.guide.generic",
            points: []
        )
    }

    /// 2系列の組から相関候補を作ります。
    ///
    /// 責務: 横軸と縦軸のService/PIDを指定した相関候補を返します。
    /// - Parameters:
    ///   - x: 横軸の(Service, PID)。
    ///   - y: 縦軸の(Service, PID)。
    /// - Returns: 検証用の相関候補。
    static func makeRelationship(x: (UInt8, UInt8), y: (UInt8, UInt8)) -> SessionPIDRelationship {
        SessionPIDRelationship(
            id: "test",
            xSeries: makeSeries(service: x.0, pid: x.1),
            ySeries: makeSeries(service: y.0, pid: y.1),
            points: []
        )
    }

    /// 開始・終了・走行距離を指定したセッションを作ります。
    ///
    /// 責務: 時間と累積走行距離だけを変えた検証用セッションを返します。
    /// - Parameters:
    ///   - start: 開始時刻(1970年からの秒)。
    ///   - end: 終了時刻(1970年からの秒)。nil なら継続中。
    ///   - startingOdometer: 開始時の累積走行距離。
    ///   - endingOdometer: 終了時の累積走行距離。
    /// - Returns: 検証用のセッション。
    static func makeSession(
        start: TimeInterval = 1_000,
        end: TimeInterval? = nil,
        startingOdometer: Double? = nil,
        endingOdometer: Double? = nil
    ) -> ConnectionSession {
        var session = ConnectionSession(accountIdentifier: "account", startedAt: Date(timeIntervalSince1970: start))
        session.endedAt = end.map { Date(timeIntervalSince1970: $0) }
        session.startingOdometerKilometers = startingOdometer
        session.endingOdometerKilometers = endingOdometer
        return session
    }

    /// 推定値を指定した走行サマリーを作ります。
    ///
    /// 責務: 推定走行時間と推定距離だけを持つ走行サマリーを返します。
    /// - Parameters:
    ///   - movingDuration: 推定走行時間。
    ///   - distance: 推定距離(km)。
    /// - Returns: 検証用の走行サマリー。
    static func makeSummary(movingDuration: TimeInterval?, distance: Double?) -> SessionPerformanceSummary {
        SessionPerformanceSummary(
            speedBands: [], rpmBands: [], estimatedMovingDuration: movingDuration, estimatedDistanceKilometers: distance
        )
    }
}
