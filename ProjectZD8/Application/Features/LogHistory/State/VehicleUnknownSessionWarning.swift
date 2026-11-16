/// 車両を特定できなかったログ(車両なし・観測VINなし)があることを知らせる警告の表示内容です。
///
/// VIN単位の未登録車両の警告(`UnassignedObservedVINWarning`)とは別枠で、件数だけを示します。
nonisolated enum VehicleUnknownSessionWarning: Equatable, Sendable {
    /// 車両不明ログが無い、またはアカウントが未確定なので表示しません。
    case hidden
    /// 車両不明ログが `count` 件あります(1以上)。
    case sessions(count: Int)
    /// 照会に失敗しました。空として扱わず、再読み込みを促します。
    case loadFailed

    /// 照会した件数から警告を作ります。
    ///
    /// 責務: 0件以下は非表示、1件以上は件数つきの警告へ変換します。
    /// - Parameter count: 車両不明ログの件数。
    init(count: Int) {
        self = count > 0 ? .sessions(count: count) : .hidden
    }

    /// 警告を表示するかどうかです。
    ///
    /// 責務: 件数ありと照会失敗だけを表示対象にします。
    var isVisible: Bool {
        self != .hidden
    }

    /// 見出しのローカライズキーです。
    ///
    /// 責務: 種類ごとの見出しキーを返し、非表示では `nil` を返します。
    var titleKey: String? {
        switch self {
        case .hidden: nil
        case .sessions: "vehicle_unknown.warning.title"
        case .loadFailed: "vehicle_unknown.warning.failure.title"
        }
    }

    /// 本文のローカライズキーです。
    ///
    /// 責務: 件数が1件か複数かで本文キーを選び、失敗では再読み込みの案内を返します。
    var messageKey: String? {
        switch self {
        case .hidden: nil
        case let .sessions(count): count == 1 ? "vehicle_unknown.warning.message.one" : "vehicle_unknown.warning.message.many"
        case .loadFailed: "unassigned_vin.warning.failure.message"
        }
    }

    /// 本文へ埋め込む値です。
    ///
    /// 責務: 件数ありでは件数を、それ以外は空を返します。
    var messageArguments: [Int] {
        guard case let .sessions(count) = self else { return [] }
        return [count]
    }

    /// 主要操作です。
    ///
    /// 責務: 件数ありでは一覧を開く操作、失敗では再読み込み、非表示では `nil` を返します。
    var primaryAction: VehicleUnknownSessionWarningPrimaryAction? {
        switch self {
        case .hidden: nil
        case .sessions: .reviewSessions
        case .loadFailed: .retryLoading
        }
    }
}
