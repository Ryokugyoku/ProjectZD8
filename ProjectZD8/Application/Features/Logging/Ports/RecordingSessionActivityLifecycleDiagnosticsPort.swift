/// 記録中の常時表示(Live Activity)の開始・終了・システムによる終了と、[切断]操作の受付を診断記録へ残すための狭い境界です。
///
/// 失敗の記録は `RecordingSessionActivityDiagnosticsPort` が担い、この境界は状態遷移だけを受け取ります。
/// 内容の更新は記録しません。車両名・VIN・写真のパス・計測値は渡しません。
@MainActor
protocol RecordingSessionActivityLifecycleDiagnosticsPort: AnyObject {
    /// 表示を開始できたことを記録します。
    ///
    /// 責務: 1件の表示開始を診断記録へ渡します。
    func activityStarted()

    /// アプリが表示を終了したことを記録します。
    ///
    /// 責務: 1件のアプリによる表示終了を診断記録へ渡します。
    func activityEnded()

    /// システムまたはユーザーに表示を閉じられたのを検知したことを記録します(8時間上限など)。
    ///
    /// 責務: 1件のアプリ以外による表示終了を診断記録へ渡します。
    func activityClosedBySystem()

    /// [切断]の要求を受け付けて停止を送ったことを記録します。
    ///
    /// 責務: 1件の受け付けた停止要求を診断記録へ渡します。
    func stopRequestAccepted()

    /// [切断]の要求を受けたが、記録中でない・停止処理中などで何もしなかったことを記録します。
    ///
    /// 責務: 1件の断った停止要求を診断記録へ渡します。
    func stopRequestDeclined()
}
