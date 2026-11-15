import CoreGraphics

/// 記録中のLive Activityで使う寸法です。
enum RecordingSessionLiveActivityMetrics {
    /// ロック画面表示の内側の余白です。
    static let contentPadding: CGFloat = 16
    /// 見出し・計測値・フッターの間隔です。
    static let sectionSpacing: CGFloat = 12
    /// 見出しの写真・車両名・経過時間の間隔です。
    static let headerSpacing: CGFloat = 12
    /// 車両名と状態文言の間隔です。
    static let titleSpacing: CGFloat = 2
    /// 状態アイコンと状態文言の間隔です。
    static let statusSpacing: CGFloat = 4
    /// ロック画面の車両写真の一辺です。
    static let photoSize: CGFloat = 56
    /// Dynamic Island(expanded)の車両写真の一辺です。
    static let expandedPhotoSize: CGFloat = 44
    /// 車両写真の角丸の半径です。
    static let photoCornerRadius: CGFloat = 10
    /// 写真が無い時のプレースホルダー背景の不透明度です。
    static let placeholderBackgroundOpacity: Double = 0.2
    /// 計測項目同士の間隔です。
    static let metricSpacing: CGFloat = 8
    /// 計測項目の見出しと値の間隔です。
    static let metricLabelSpacing: CGFloat = 2
    /// 計測値と単位の間隔です。
    static let unitSpacing: CGFloat = 2
    /// 経過時間の表示に確保する最小幅です。
    static let timerMinWidth: CGFloat = 64
}
