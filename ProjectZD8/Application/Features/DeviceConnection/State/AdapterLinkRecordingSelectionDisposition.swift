/// 通知の[記録開始]の選択を、監視がどう扱うかの判定結果です。
nonisolated enum AdapterLinkRecordingSelectionDisposition: Equatable, Sendable {
    /// 状態機械へそのまま渡します(検知待ちなら記録を始め、記録中・終了処理中・抑止中なら無視されます)。
    case forwardToTransition
    /// 有効期限つきの「記録開始の意思」として保持し、期限内の検知の完了で記録を始めます。
    case keepAsIntent
    /// 処理できないので捨て、理由を通知します。
    case reject(AdapterLinkRecordingStartFailureReason)
}
