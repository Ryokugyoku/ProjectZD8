import Foundation

/// 統合ログ(`Logger`・`OSLog`)の subsystem を、アプリ全体で1つの値に揃えるための定数です。
///
/// 値はアプリの bundle ID です(取得できなければ `ProjectZD8`)。category は各出力元が決めます。
/// actor の `nonisolated` な static logger からも参照できるよう、型と定数をメインアクターから切り離しています。
nonisolated enum DiagnosticsLogSubsystem {
    /// すべての `Logger` と `OSLog` の生成時に渡す subsystem の値です。
    static let identifier: String = Bundle.main.bundleIdentifier ?? "ProjectZD8"
}
