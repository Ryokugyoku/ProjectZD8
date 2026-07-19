import Foundation

/// 検証済み定義で数値化した1件のOBD PID観測です。
struct OBDPIDSample: Equatable, Identifiable, Sendable {
    /// Service/PIDの複合識別子です。
    let request: OBDPIDRequest
    /// 表示名へ解決できる安定キーです。
    let nameKey: String
    /// 定義式を適用した数値です。
    let value: Double
    /// 定義に含まれる単位です。
    let unit: String
    /// 観測完了日時です。
    let observedAt: Date
    /// 項目概要のローカライズキーです。
    let summaryKey: String
    /// 高値時説明のローカライズキーです。
    let highValueKey: String
    /// 低値時説明のローカライズキーです。
    let lowValueKey: String
    /// 相関項目説明のローカライズキーです。
    let correlationKey: String

    /// SwiftUI表示で使用するService/PID識別子です。
    var id: OBDPIDRequest { request }

    /// 数値化済みPID観測を生成します。
    ///
    /// 責務: 1件のService/PID数値を名称、単位、観測日時と同じ不変値へ固定します。
    /// - Parameters:
    ///   - request: Service/PIDの複合識別子。
    ///   - nameKey: ローカライズ用名称キー。
    ///   - value: 定義式適用後の数値。
    ///   - unit: 数値の単位。
    ///   - observedAt: 観測完了日時。
    ///   - summaryKey: 項目概要のローカライズキー。
    ///   - highValueKey: 高値時説明のローカライズキー。
    ///   - lowValueKey: 低値時説明のローカライズキー。
    ///   - correlationKey: 相関項目説明のローカライズキー。
    init(request: OBDPIDRequest, nameKey: String, value: Double, unit: String, observedAt: Date, summaryKey: String = "obd.pid.help.unconfirmed.summary", highValueKey: String = "obd.pid.help.unconfirmed.high", lowValueKey: String = "obd.pid.help.unconfirmed.low", correlationKey: String = "obd.pid.help.unconfirmed.correlation") {
        self.request = request
        self.nameKey = nameKey
        self.value = value
        self.unit = unit
        self.observedAt = observedAt
        self.summaryKey = summaryKey
        self.highValueKey = highValueKey
        self.lowValueKey = lowValueKey
        self.correlationKey = correlationKey
    }
}
