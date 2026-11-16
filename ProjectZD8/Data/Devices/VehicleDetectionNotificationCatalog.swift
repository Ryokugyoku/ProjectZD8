/// 車両検知の監視通知の識別子・カテゴリ・文言キー・割り込みレベルを決める純粋な定義です。
///
/// 通知センターに依存しないので、iOS実装の外(macOSのテスト)から内容を検証できます。
nonisolated struct VehicleDetectionNotificationCatalog: Sendable {
    /// [記録開始]操作を持つ通知カテゴリの識別子です。
    static let categoryIdentifier = "VEHICLE_DETECTION"
    /// [記録開始]操作の識別子です。
    static let startRecordingActionIdentifier = "VEHICLE_DETECTION_START_RECORDING"
    /// [記録開始]操作の表示名のローカライズキーです。
    static let startRecordingActionTitleKey = "vehicle-detection-start-recording-action"
    /// 「車両を検知しました」通知の固定識別子です。
    static let vehicleDetectedIdentifier = "VEHICLE_DETECTION_DETECTED"
    /// 「記録を開始しました」通知の固定識別子です。
    static let recordingStartedIdentifier = "VEHICLE_DETECTION_RECORDING_STARTED"
    /// 「記録を開始できませんでした」通知の固定識別子です。取り下げ(`allIdentifiers`)には含めず、次の同じ通知で置き換えます。
    static let recordingStartFailedIdentifier = "VEHICLE_DETECTION_RECORDING_START_FAILED"
    /// 監視通知の全識別子です。取り下げと置き換えで使います。
    static let allIdentifiers = [vehicleDetectedIdentifier, recordingStartedIdentifier]

    /// 「車両を検知しました」通知の内容を作ります。
    ///
    /// 責務: [記録開始]操作付き・Time Sensitive・固定識別子の内容へ変換し、VINの有無で本文を選びます。
    /// - Parameter vin: 読み取ったVIN。読めなかった場合は `nil`。
    /// - Returns: 通知内容。
    func vehicleDetected(vin: String?) -> VehicleDetectionNotificationContent {
        VehicleDetectionNotificationContent(
            identifier: Self.vehicleDetectedIdentifier,
            categoryIdentifier: Self.categoryIdentifier,
            titleKey: "vehicle-detection-detected-title",
            bodyKey: vin == nil ? "vehicle-detection-detected-body" : "vehicle-detection-detected-body-vin",
            bodyArguments: vin.map { [$0] } ?? [],
            interruptionLevel: .timeSensitive
        )
    }

    /// 「記録を開始しました」通知の内容を作ります。
    ///
    /// 責務: 操作の無い・固定識別子の内容へ変換し、VINの有無で本文を選びます。
    /// - Parameter vin: 読み取ったVIN。読めなかった場合は `nil`。
    /// - Returns: 通知内容。
    func recordingStarted(vin: String?) -> VehicleDetectionNotificationContent {
        VehicleDetectionNotificationContent(
            identifier: Self.recordingStartedIdentifier,
            categoryIdentifier: nil,
            titleKey: "vehicle-detection-recording-started-title",
            bodyKey: vin == nil ? "vehicle-detection-recording-started-body" : "vehicle-detection-recording-started-body-vin",
            bodyArguments: vin.map { [$0] } ?? [],
            interruptionLevel: .active
        )
    }

    /// 「記録を開始できませんでした」通知の内容を作ります。
    ///
    /// 責務: 操作の無い・固定識別子・割り込みレベル `.active` の内容へ変換し、理由で本文を選びます。
    /// - Parameter reason: 記録を始められなかった理由。
    /// - Returns: 通知内容。
    func recordingStartFailed(reason: AdapterLinkRecordingStartFailureReason) -> VehicleDetectionNotificationContent {
        VehicleDetectionNotificationContent(
            identifier: Self.recordingStartFailedIdentifier,
            categoryIdentifier: nil,
            titleKey: "vehicle-detection-recording-start-failed-title",
            bodyKey: reason.bodyKey,
            bodyArguments: [],
            interruptionLevel: .active
        )
    }

    /// 提示前に取り除く他の監視通知の識別子を返します。
    ///
    /// 責務: 監視通知を常に1件だけにするため、提示する通知以外の監視通知の識別子を返します。
    /// - Parameter content: これから提示する通知内容。
    /// - Returns: 取り除く識別子。
    func identifiersReplaced(by content: VehicleDetectionNotificationContent) -> [String] {
        Self.allIdentifiers.filter { $0 != content.identifier }
    }

    /// 通知への応答が[記録開始]の選択かどうかを判定します。
    ///
    /// 責務: 監視カテゴリの[記録開始]操作だけを記録開始の選択とし、本文タップや他の通知の操作は含めません。
    /// - Parameters:
    ///   - actionIdentifier: 選ばれた操作の識別子。
    ///   - categoryIdentifier: 応答した通知のカテゴリ識別子。
    /// - Returns: [記録開始]の選択なら `true`。
    func isRecordingStartSelection(actionIdentifier: String, categoryIdentifier: String) -> Bool {
        actionIdentifier == Self.startRecordingActionIdentifier && categoryIdentifier == Self.categoryIdentifier
    }
}
