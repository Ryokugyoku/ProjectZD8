/// 記録中のLive Activityで使うSF Symbolの名前です。SwiftUIに依存しない純粋型で、アプリとWidget Extensionの両方に属します。
nonisolated enum RecordingSessionLiveActivityStatusSymbol {
    /// [切断]ボタンのアイコン名です。
    static let stopActionName = "stop.circle.fill"
    /// 車両写真が無い時のプレースホルダーのアイコン名です。
    static let photoPlaceholderName = "car.fill"

    /// 状態の強調に対応するアイコン名を返します。
    ///
    /// 責務: 状態欄の強調を状態アイコンのSF Symbol名へ変換します。
    /// - Parameter tone: 状態欄の強調。
    /// - Returns: 通常は記録中の丸、警告は注意の三角。
    static func name(for tone: RecordingSessionActivityAttributes.StatusTone) -> String {
        switch tone {
        case .normal: "record.circle"
        case .warning: "exclamationmark.triangle.fill"
        }
    }
}
