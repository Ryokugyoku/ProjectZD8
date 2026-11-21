import Foundation
@testable import ProjectZD8

/// 解析の PID の時系列(`SessionLogAnalysisState.TimelineSample`)を作るテストの補助です。
enum RouteAnalysisTimelineSampleFixtures {
    /// 時系列の1件を作ります。
    ///
    /// 責務: 指定の連番・時刻・Service・PID・値・単位・単調時刻を持ち、応答データが空で失敗理由の無いサンプルを返します。
    /// - Parameters:
    ///   - sequence: Raw ログの順序。
    ///   - observedAt: 観測した実時間。
    ///   - service: OBD Service 番号。
    ///   - pid: PID 番号。
    ///   - value: 数式変換後の値。
    ///   - unit: 単位。
    ///   - monotonicNanoseconds: 単調時刻(ナノ秒)。
    /// - Returns: サンプル。
    static func sample(
        sequence: Int64,
        observedAt: Date,
        service: UInt8 = 0x01,
        pid: UInt8 = 0x0D,
        value: Double?,
        unit: String? = "km/h",
        monotonicNanoseconds: UInt64? = nil
    ) -> SessionLogAnalysisState.TimelineSample {
        SessionLogAnalysisState.TimelineSample(
            sequence: sequence,
            observedAt: observedAt,
            service: service,
            pid: pid,
            nameKey: nil,
            value: value,
            unit: unit,
            payload: [],
            decodingFailure: nil,
            monotonicNanoseconds: monotonicNanoseconds
        )
    }

    /// 秒をナノ秒の単調時刻へ直します。
    ///
    /// 責務: 0 以上の整数秒をナノ秒に換算します(小数の誤差を持ち込まないため整数で受けます)。
    /// - Parameter seconds: 単調時刻の秒。
    /// - Returns: ナノ秒。
    static func nanoseconds(_ seconds: UInt64) -> UInt64 {
        seconds * 1_000_000_000
    }
}
