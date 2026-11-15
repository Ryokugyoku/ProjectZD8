#if os(iOS)
import Foundation

/// 未登録車両の警告本文をローカライズ済みの文字列へ整形します。
enum IOSUnassignedObservedVINWarningMessageFormatter {
    /// 警告本文を返します。
    ///
    /// 責務: 警告の本文キーと件数引数を、現在の言語の書式で1件の文字列へ変換します。
    /// - Parameters:
    ///   - warning: 整形する警告。
    ///   - locale: 数値の書式に使うロケール。
    /// - Returns: 本文。非表示の警告では `nil`。
    static func message(
        for warning: UnassignedObservedVINWarning,
        locale: Locale = .autoupdatingCurrent
    ) -> String? {
        guard let key = warning.messageKey else { return nil }
        let format = String(localized: String.LocalizationValue(key))
        let arguments = warning.messageArguments.map { $0 as any CVarArg }
        return arguments.isEmpty ? format : String(format: format, locale: locale, arguments: arguments)
    }
}
#endif
