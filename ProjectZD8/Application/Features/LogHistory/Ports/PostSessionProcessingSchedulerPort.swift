/// 記録セッション終了後の後処理(アップロードとRawキャッシュの整理)の実行を、OSへ予約する狭い境界です。
///
/// 実行の判断は `RunPostSessionProcessingUseCase` が行い、この境界は予約の受け渡しだけを担います。
@MainActor
protocol PostSessionProcessingSchedulerPort: AnyObject {
    /// 後処理の実行をOSへ予約します。予約済みの要求があれば置き換えます。
    ///
    /// 責務: 1件の実行予約をOSへ渡します。
    /// - Parameter requiresNetworkConnectivity: ネットワーク接続を実行条件にする場合は `true`。
    /// - Throws: OSが予約を受け付けなかった場合のエラー。
    func schedule(requiresNetworkConnectivity: Bool) throws
}
