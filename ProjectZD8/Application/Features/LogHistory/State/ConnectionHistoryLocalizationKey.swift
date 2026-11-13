/// 接続履歴の終了理由を固定ローカライズキーへ変換します。
extension ConnectionSessionEndReason {
    /// String Catalogへ登録済みの終了理由キーです。
    var historyLocalizationKey: String {
        switch self {
        case .userDisconnected: "history.reason.userDisconnected"
        case .vehicleNoResponse: "history.reason.vehicleNoResponse"
        case .connectionLost: "history.reason.connectionLost"
        case .acquisitionFailed: "history.reason.acquisitionFailed"
        case .superseded: "history.reason.superseded"
        case .accountSignedOut: "history.reason.accountSignedOut"
        case .unexpectedTermination: "history.reason.unexpectedTermination"
        }
    }
}

/// 接続履歴の終了理由条件を固定ローカライズキーへ変換します。
extension ConnectionHistoryEndReasonFilter {
    /// String Catalogへ登録済みの終了理由条件キーです。
    var historyLocalizationKey: String {
        switch self {
        case .all: "history.reason.all"
        case .userDisconnected: "history.reason.userDisconnected"
        case .vehicleNoResponse: "history.reason.vehicleNoResponse"
        case .connectionLost: "history.reason.connectionLost"
        case .acquisitionFailed: "history.reason.acquisitionFailed"
        case .superseded: "history.reason.superseded"
        case .accountSignedOut: "history.reason.accountSignedOut"
        case .unexpectedTermination: "history.reason.unexpectedTermination"
        }
    }
}

/// 接続履歴の並び順を固定ローカライズキーへ変換します。
extension ConnectionHistorySortOrder {
    /// String Catalogへ登録済みの並び順キーです。
    var historyLocalizationKey: String {
        switch self {
        case .newest: "history.sort.newest"
        case .oldest: "history.sort.oldest"
        case .longestDuration: "history.sort.longestDuration"
        case .shortestDuration: "history.sort.shortestDuration"
        }
    }
}
