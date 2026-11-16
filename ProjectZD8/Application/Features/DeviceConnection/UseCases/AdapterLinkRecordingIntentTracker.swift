/// 検知待ち以外で届いた[記録開始]の選択を、有効期限つきの「記録開始の意思」として保持し、使う・捨てる・期限切れを知らせます。
///
/// 判定(扱い方・有効期限・理由)は `AdapterLinkRecordingIntentPolicy` に任せ、この型は意思の保持と期限の待ち、
/// 捨てた時の「記録を開始できませんでした」通知だけを行います。意思は検知の完了で1回だけ使われ、使わなくても消えます。
@MainActor
final class AdapterLinkRecordingIntentTracker {
    /// 保持している意思です。無ければ `nil` です。
    private(set) var intent: AdapterLinkRecordingIntent?

    /// 扱い方と有効期限の判定です。
    let policy: AdapterLinkRecordingIntentPolicy

    /// 現在時刻と待機の能力です(単調時計基準)。
    private let clock: any AdapterLinkSupervisionClock

    /// 理由を示す通知の送り先です。
    private let notifications: any VehicleDetectionNotificationPort

    /// 有効期限の満了を確かめる待ちです。
    private var expiryTask: Task<Void, Never>?

    /// 判定・時計・通知を注入して生成します。
    ///
    /// 責務: 意思の保持に使う依存関係を固定します。
    /// - Parameters:
    ///   - policy: 扱い方と有効期限の判定。
    ///   - clock: 現在時刻と待機の能力。
    ///   - notifications: 理由を示す通知の送り先。
    init(
        policy: AdapterLinkRecordingIntentPolicy = AdapterLinkRecordingIntentPolicy(),
        clock: any AdapterLinkSupervisionClock,
        notifications: any VehicleDetectionNotificationPort
    ) {
        self.policy = policy
        self.clock = clock
        self.notifications = notifications
    }

    /// 選択を意思として保持し、有効期限の満了を待ち始めます。
    ///
    /// 責務: 現在時刻を起点に意思を置き換え、期限の1ミリ秒後に満了を確かめる待ちを始めます(前の待ちは取り消します)。
    func keep() {
        intent = AdapterLinkRecordingIntent(selectedAt: clock.now)
        expiryTask?.cancel()
        let delay = policy.expiryCheckDelay
        expiryTask = Task { [weak self, clock] in
            do {
                try await clock.sleep(for: delay)
            } catch {
                return
            }
            self?.expireIfNeeded()
        }
    }

    /// 保持している意思が現在有効かどうかを返します。
    ///
    /// 責務: 意思があり、有効期限内(ちょうど2分を含む)であることを判定します。
    var hasValidIntent: Bool {
        guard let intent else { return false }
        return policy.isValid(intent, now: clock.now)
    }

    /// 検知の完了(VIN読取の完了)で意思を使い終えます。
    ///
    /// 責務: 有効な意思は使われたものとして黙って消し、期限切れの意思は捨てて「車両を検知できなかった」を知らせます。
    func detectionDidComplete() {
        guard intent != nil else { return }
        if hasValidIntent {
            clear()
        } else {
            reject(.vehicleNotDetected)
        }
    }

    /// 意思を捨て、理由を知らせます。
    ///
    /// 責務: 意思があれば消して理由つきの通知を出します。意思が無ければ何もしません。
    /// - Parameter reason: 捨てた理由。
    func discard(_ reason: AdapterLinkRecordingStartFailureReason) {
        guard intent != nil else { return }
        reject(reason)
    }

    /// 選択そのものを処理できなかったことを知らせます。
    ///
    /// 責務: 意思を保持せずに、理由つきの通知を出します。
    /// - Parameter reason: 処理できなかった理由。
    func rejectSelection(_ reason: AdapterLinkRecordingStartFailureReason) {
        notifications.presentRecordingStartFailed(reason: reason)
    }

    /// 有効期限の待ちが明けた時に、期限切れなら意思を捨てます。
    ///
    /// 責務: 待ちが明けても期限内(時計が進んでいない場合)なら何もしません。
    private func expireIfNeeded() {
        guard intent != nil, !hasValidIntent else { return }
        reject(.vehicleNotDetected)
    }

    /// 意思を消して理由つきの通知を出します。
    ///
    /// 責務: 保持と待ちを片付けてから通知します。
    /// - Parameter reason: 捨てた理由。
    private func reject(_ reason: AdapterLinkRecordingStartFailureReason) {
        clear()
        notifications.presentRecordingStartFailed(reason: reason)
    }

    /// 意思と期限の待ちを片付けます。
    ///
    /// 責務: 保持を消し、待ちを取り消します。
    private func clear() {
        intent = nil
        expiryTask?.cancel()
        expiryTask = nil
    }
}
