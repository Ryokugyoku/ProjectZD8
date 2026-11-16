/// 監視通知の提示・取り下げの世代を、通知の種類ごとに分けて数える純粋な値です。
///
/// 非同期の提示が、後から来た同じ種類の提示や取り下げを追い越さないために使います。監視通知(検知・開始)と
/// 「記録を開始できませんでした」は別の世代で数えるので、失敗の通知の提示が進行中の検知通知の提示を捨てることはありません。
/// 取り下げは監視通知だけを対象にし、失敗の通知の世代は進めません。
nonisolated struct VehicleDetectionNotificationRequestGenerations: Equatable, Sendable {
    /// 監視通知(検知・開始)の世代です。
    private(set) var supervision: UInt64 = 0
    /// 「記録を開始できませんでした」の世代です。
    private(set) var recordingStartFailure: UInt64 = 0

    /// どの種類も世代0で生成します。
    ///
    /// 責務: まだ提示も取り下げもしていない状態を構築します。
    init() {}

    /// 指定した識別子の通知を提示する時に、その種類の世代を進めて返します。
    ///
    /// 責務: 失敗の通知なら失敗の世代を、それ以外は監視通知の世代を1つ進めます。
    /// - Parameter identifier: 提示する通知の識別子。
    /// - Returns: 進めた後の、その種類の世代。
    mutating func advance(forPresenting identifier: String) -> UInt64 {
        if Self.isRecordingStartFailure(identifier) {
            recordingStartFailure &+= 1
            return recordingStartFailure
        }
        supervision &+= 1
        return supervision
    }

    /// 監視通知の取り下げで、監視通知の世代を進めます。
    ///
    /// 責務: 進行中の監視通知の提示を古いものにします。失敗の通知の世代は変えません。
    mutating func advanceForDismissal() {
        supervision &+= 1
    }

    /// 提示を要求した時点の世代が、その種類の最新の世代かどうかを返します。
    ///
    /// 責務: 同じ種類の後の提示・取り下げ(監視通知のみ)が無かったことを判定します。
    /// - Parameters:
    ///   - generation: 提示を要求した時点の世代。
    ///   - identifier: 提示する通知の識別子。
    /// - Returns: 最新なら `true`。
    func isCurrent(_ generation: UInt64, forPresenting identifier: String) -> Bool {
        generation == (Self.isRecordingStartFailure(identifier) ? recordingStartFailure : supervision)
    }

    /// 識別子が「記録を開始できませんでした」かどうかを返します。
    ///
    /// 責務: 失敗の通知の固定識別子と一致するかを判定します。
    /// - Parameter identifier: 通知の識別子。
    /// - Returns: 失敗の通知なら `true`。
    private static func isRecordingStartFailure(_ identifier: String) -> Bool {
        identifier == VehicleDetectionNotificationCatalog.recordingStartFailedIdentifier
    }
}
