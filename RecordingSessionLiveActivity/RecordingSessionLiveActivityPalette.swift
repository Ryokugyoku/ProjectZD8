import SwiftUI

/// 記録中のLive Activityの色です。アクセントはシアン、警告だけオレンジです。
enum RecordingSessionLiveActivityPalette {
    /// アクセント色(シアン)です。
    static let accent = Color.cyan
    /// 警告の強調色(オレンジ)です。
    static let warning = Color.orange

    /// 状態の強調に対応する色を返します。
    ///
    /// 責務: 状態欄の強調を表示色へ変換します。
    /// - Parameter tone: 状態欄の強調。
    /// - Returns: 通常はシアン、警告はオレンジ。
    static func tint(for tone: RecordingSessionActivityAttributes.StatusTone) -> Color {
        switch tone {
        case .normal: accent
        case .warning: warning
        }
    }
}
