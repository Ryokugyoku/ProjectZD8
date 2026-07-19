import Foundation

/// 1件の標準OBD PIDを数値へ変換するための永続化可能な定義です。
struct OBDPIDDefinition: Equatable, Sendable {
    /// OBD要求のService番号です。
    let service: UInt8
    /// Service内のPID番号です。
    let pid: UInt8
    /// 表示名へ解決できる安定キーです。
    let nameKey: String
    /// 数式が参照する応答データの必要バイト数です。
    let requiredByteCount: Int
    /// `A`から`H`までのバイト変数を使用する制限付き数式です。
    let formula: String
    /// 計算結果の単位です。
    let unit: String
    /// 規格上または定義上の最小値です。
    let minimumValue: Double?
    /// 規格上または定義上の最大値です。
    let maximumValue: Double?
    /// 定義を確認した一次資料のURI文字列です。
    let sourceURI: String
    /// 同じService/PID定義を更新するときの単調増加改訂番号です。
    let revision: Int

    /// 数式を含むPID定義を生成します。
    ///
    /// 責務: 1件のPID識別子と変換契約を不変値として固定します。
    /// - Parameters:
    ///   - service: OBD要求のService番号。
    ///   - pid: Service内のPID番号。
    ///   - nameKey: 表示名の安定キー。
    ///   - requiredByteCount: 数式評価に必要なバイト数。
    ///   - formula: 制限付き数式。
    ///   - unit: 計算結果の単位。
    ///   - minimumValue: 許容最小値。
    ///   - maximumValue: 許容最大値。
    ///   - sourceURI: 一次資料のURI文字列。
    ///   - revision: 定義の改訂番号。
    init(
        service: UInt8,
        pid: UInt8,
        nameKey: String,
        requiredByteCount: Int,
        formula: String,
        unit: String,
        minimumValue: Double?,
        maximumValue: Double?,
        sourceURI: String,
        revision: Int
    ) {
        self.service = service
        self.pid = pid
        self.nameKey = nameKey
        self.requiredByteCount = requiredByteCount
        self.formula = formula
        self.unit = unit
        self.minimumValue = minimumValue
        self.maximumValue = maximumValue
        self.sourceURI = sourceURI
        self.revision = revision
    }
}
