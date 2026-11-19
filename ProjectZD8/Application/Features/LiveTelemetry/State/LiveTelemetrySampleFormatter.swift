import Foundation

/// PIDの現在値を、指定したロケールの数値文字列へ整形します。
///
/// iOSとmacOSで共通の整形規則です。View は `@Environment(\.locale)` を渡し、`Text(verbatim:)` で表示します。
nonisolated struct LiveTelemetrySampleFormatter: Equatable, Sendable {
    /// 状態を持たない整形器を生成します。
    ///
    /// 責務: 整形規則だけを持つ値を用意します。
    init() {}

    /// 主要値カードの数値を整形します。
    ///
    /// 責務: 1件のPID値を小数0〜1桁の数値文字列へ変換します。
    /// - Parameters:
    ///   - sample: 整形するPIDサンプル。
    ///   - locale: 小数点と桁区切りを決めるロケール。
    /// - Returns: 単位を含まない数値文字列。
    func primaryValueText(_ sample: OBDPIDSample, locale: Locale) -> String {
        sample.value.formatted(.number.precision(.fractionLength(0...1)).locale(locale))
    }

    /// 詳細カードの数値を整形します。
    ///
    /// 責務: 1件のPID値を小数0〜2桁の数値文字列へ変換します。
    /// - Parameters:
    ///   - sample: 整形するPIDサンプル。
    ///   - locale: 小数点と桁区切りを決めるロケール。
    /// - Returns: 単位を含まない数値文字列。
    func detailValueText(_ sample: OBDPIDSample, locale: Locale) -> String {
        sample.value.formatted(.number.precision(.fractionLength(0...2)).locale(locale))
    }

    /// 詳細カードの数値と単位を1行へ整形します。
    ///
    /// 責務: 1件のPID値を小数0〜2桁の数値と単位の文字列へ変換します。
    /// - Parameters:
    ///   - sample: 整形するPIDサンプル。
    ///   - locale: 小数点と桁区切りを決めるロケール。
    /// - Returns: `"<数値> <単位>"`。単位が空なら数値だけ。
    func detailValueWithUnitText(_ sample: OBDPIDSample, locale: Locale) -> String {
        let value = detailValueText(sample, locale: locale)
        return sample.unit.isEmpty ? value : "\(value) \(sample.unit)"
    }
}
