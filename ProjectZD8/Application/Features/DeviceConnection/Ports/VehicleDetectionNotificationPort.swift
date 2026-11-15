/// 車両検知と記録開始をユーザーへ知らせるシステム通知の能力です。
@MainActor
protocol VehicleDetectionNotificationPort: AnyObject {
    /// 通知の許可・カテゴリ・[記録開始]操作の受け口を準備します。
    ///
    /// 責務: 車両検知通知を提示でき、[記録開始]の選択を受け取れるシステム状態を整えます。
    /// - Parameter recordingStartSelected: ユーザーが[記録開始]を選んだときに呼ぶ処理。
    /// - Returns: 通知の提示が許可されている場合は `true`。
    /// - Side Effects: 初回は通知許可ダイアログを表示できます。
    func prepare(recordingStartSelected: @escaping @MainActor () -> Void) async -> Bool

    /// 「車両を検知しました」通知を提示します。提示済みの監視通知は置き換えます。
    ///
    /// 責務: 1件の検知を[記録開始]操作付きの通知へ変換します。
    /// - Parameter vin: 読み取ったVIN。読めなかった場合は `nil`。
    func presentVehicleDetected(vin: String?)

    /// 「記録を開始しました」通知を提示します。提示済みの監視通知は置き換えます。
    ///
    /// 責務: 自動記録による記録開始をユーザーへ知らせます。
    /// - Parameter vin: 読み取ったVIN。読めなかった場合は `nil`。
    func presentRecordingStarted(vin: String?)

    /// 提示中の監視通知を取り下げます。
    ///
    /// 責務: 車両検知通知と記録開始通知を通知センターから取り除きます。
    func dismiss()
}
