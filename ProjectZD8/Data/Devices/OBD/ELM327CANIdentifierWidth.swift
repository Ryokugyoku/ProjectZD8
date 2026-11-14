import Foundation

/// ELM/STNコマンドで扱うCAN IDの幅と16進桁数です。
nonisolated enum ELM327CANIdentifierWidth: Equatable, Sendable {
    /// 11bit標準ID(16進3桁)です。
    case standard
    /// 29bit拡張ID(16進8桁)です。
    case extended

    /// CAN IDの値から幅を決めます。
    ///
    /// 責務: `0x7FF`以下を11bit、`0x800...0x1FFFFFFF`を29bitとし、範囲外を拒否します。
    /// - Parameter identifier: 判定するCAN ID。
    init?(identifier: UInt32) {
        if identifier <= ELM327CANIdentifierWidth.standard.maximumValue {
            self = .standard
        } else if identifier <= ELM327CANIdentifierWidth.extended.maximumValue {
            self = .extended
        } else {
            return nil
        }
    }

    /// 拡張IDかどうかから幅を決めます。
    ///
    /// 責務: 真偽値を11bit/29bitの幅へ変換します。
    /// - Parameter isExtended: 29bit拡張IDならtrue。
    init(isExtended: Bool) {
        self = isExtended ? .extended : .standard
    }

    /// この幅で表せる最大値(全ビットマスク)です。
    var maximumValue: UInt32 {
        switch self {
        case .standard: 0x7FF
        case .extended: 0x1FFF_FFFF
        }
    }

    /// コマンド文字列での16進桁数です。
    var hexadecimalDigitCount: Int {
        switch self {
        case .standard: 3
        case .extended: 8
        }
    }

    /// 値がこの幅に収まるかどうかを判定します。
    ///
    /// 責務: 値が幅の最大値以下かを返します。
    /// - Parameter value: 判定するID・パターン・マスク値。
    /// - Returns: 幅に収まればtrue。
    func contains(_ value: UInt32) -> Bool {
        value <= maximumValue
    }

    /// 値をこの幅の桁数で大文字16進文字列へ整形します。
    ///
    /// 責務: 幅に応じたゼロ埋め桁数で16進表記を作ります。
    /// - Parameter value: 整形する値。
    /// - Returns: 3桁または8桁の大文字16進文字列。
    func hexadecimalString(_ value: UInt32) -> String {
        String(format: "%0\(hexadecimalDigitCount)X", value)
    }
}
