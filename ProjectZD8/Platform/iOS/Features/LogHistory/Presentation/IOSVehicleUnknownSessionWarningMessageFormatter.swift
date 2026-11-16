#if os(iOS)
import Foundation

/// 車両不明ログの警告の本文を、ローカライズ済みの文言と件数から組み立てるiOSの整形です。
enum IOSVehicleUnknownSessionWarningMessageFormatter {
    /// 警告の本文を返します。
    ///
    /// 責務: 本文キーをローカライズし、件数があれば書式へ埋め込みます。
    /// - Parameters:
    ///   - warning: 表示する警告。
    ///   - locale: 数値の書式に使うロケール。
    /// - Returns: 本文。本文の無い警告では `nil`。
    static func message(for warning: VehicleUnknownSessionWarning, locale: Locale = .autoupdatingCurrent) -> String? {
        guard let key = warning.messageKey else { return nil }
        let format = String(localized: String.LocalizationValue(key))
        let arguments = warning.messageArguments.map { $0 as any CVarArg }
        return arguments.isEmpty ? format : String(format: format, locale: locale, arguments: arguments)
    }
}
#endif
