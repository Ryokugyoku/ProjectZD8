/// 車両検知時に記録をどう始めるかの選択肢です。
enum AutomaticRecordingChoice: String, CaseIterable, Identifiable, Equatable, Sendable {
    /// 検知を通知し、通知の[記録開始]を選んだ時に記録を始めます(自動記録オフ)。
    case startFromNotification

    /// 検知したらそのまま記録を始めます(自動記録オン)。
    case startAutomatically

    /// 保存済みの自動記録設定から選択肢を生成します。
    ///
    /// 責務: 自動記録設定の真偽値を対応する1件の選択肢へ写像します。
    /// - Parameter isAutomaticRecordingEnabled: 自動記録が有効なら `true`。
    init(isAutomaticRecordingEnabled: Bool) {
        self = isAutomaticRecordingEnabled ? .startAutomatically : .startFromNotification
    }

    /// 一覧表示とアクセシビリティ参照に使う安定識別子です。
    var id: String { rawValue }

    /// 自動記録設定として保存する値です。自動で開始する場合だけ `true` です。
    var isAutomaticRecordingEnabled: Bool {
        switch self {
        case .startFromNotification:
            false
        case .startAutomatically:
            true
        }
    }

    /// 選択肢の名称を表すローカライズキーです。
    var titleKey: String {
        switch self {
        case .startFromNotification:
            "automatic_recording.choice.notification.title"
        case .startAutomatically:
            "automatic_recording.choice.automatic.title"
        }
    }

    /// 選択肢の動作の違いを短く説明するローカライズキーです。
    var descriptionKey: String {
        switch self {
        case .startFromNotification:
            "automatic_recording.choice.notification.description"
        case .startAutomatically:
            "automatic_recording.choice.automatic.description"
        }
    }

    /// 選択肢を表すSF Symbol名です。
    var systemImageName: String {
        switch self {
        case .startFromNotification:
            "bell.badge.fill"
        case .startAutomatically:
            "record.circle.fill"
        }
    }
}
