/// 車両検知後、VIN読取の完了前か、ユーザーの記録開始操作待ちかを表します。
nonisolated enum AdapterLinkVehicleDetectionPhase: Equatable, Sendable {
    /// ECU応答を確認し、VINを読み取っています。通知はまだ提示していません。
    case readingVIN

    /// 「車両を検知しました」通知を提示し、[記録開始]の選択を待っています。
    case awaitingRecordingStart
}
