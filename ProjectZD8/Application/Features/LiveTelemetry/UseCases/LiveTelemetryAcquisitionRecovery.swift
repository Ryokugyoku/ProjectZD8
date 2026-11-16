/// 取得が途切れた後、回復段階を順に試し、使い切ったら一時停止して猶予内の復帰を待つ手順です。
///
/// 一時停止中は通知(フォアグラウンド復帰・リンク復帰)に加え、`AcquisitionGracePeriodPolicy.retryIntervalNanoseconds`
/// ごとに復帰を試します。車両の無応答やシリアル接続のように通知が来ない場合も、猶予内の復帰を検知するためです。
/// 回復段階の最中に届いたリンク復帰は通り道が閉じていて失われるため、一時停止に入る時点のリンク可用性を参照し、
/// 使えると分かっていれば待たずに1回試します(`LiveTelemetryPauseWakeEvaluator.entryReason(for:linkAvailability:)`)。
///
/// 猶予の起点は一時停止に入った時点ではなく最後に正応答を受信した時点で、判定は `LiveTelemetryReceiveGrace` に任せます。
/// 回復段階でも一時停止中でも、試行を始める前に期限を過ぎていれば試行せずに猶予切れとし、試行が成功した場合も
/// 成功が確定した時点の経過で判定します。一時停止に入る時点で既に期限を過ぎていれば、試行も待機もせずに猶予切れとします。
///
/// 回復段階の進め方は `LiveTelemetryRecoveryProgress`(`AcquisitionStallPolicy`)、一時停止中の判定は
/// `LiveTelemetryPauseWakeEvaluator`(`AcquisitionGracePeriodPolicy`)に任せ、この型は副作用の順序づけだけを行います。
/// 回復操作の成功はアダプターとの通信を立て直せたことだけを表すため、続けて1件の要求(確認要求)を送り、
/// 正応答を得たときだけ復帰とします。確認要求の応答は区間が閉じている間のものなので記録しません。
///
/// 応答途絶の回復で、回復操作が成功する(アダプターは応答する)のに確認要求が正応答にならない状態は、
/// 車両が応答しない(エンジン停止)とみなし、猶予を `LiveTelemetryReceiveGrace.suspectVehicleOff()` で縮めます。
/// 以後は最後の受信から「エンジン停止とみなす時間」に達した時点で猶予切れとします。リンク断と、回復操作が失敗する場合は縮めません。
nonisolated struct LiveTelemetryAcquisitionRecovery: Sendable {
    /// 回復を終えた結果です。
    enum Outcome: Equatable, Sendable {
        /// 車両の応答を確かめて復帰しました。
        case resumed(ConnectionSessionSegmentStartReason)
        /// 猶予を超えても復帰しませんでした。
        case expired
    }

    /// 回復操作の境界です。
    private let linkRecovery: any LiveTelemetryLinkRecoveryPort
    /// 確認要求を送る読取部品です。
    private let reader: OBDPIDSingleRequestReader
    /// 猶予を判定する単調時計です。
    private let clock: any MonotonicClockPort
    /// 猶予切れの期限と定期試行の時刻まで待つ境界です。
    private let deadlineWaiter: any LiveTelemetryDeadlineWaitPort
    /// 一時停止中の起床判定です。
    private let wakeEvaluator = LiveTelemetryPauseWakeEvaluator()

    /// 回復に使う境界を固定します。
    ///
    /// 責務: 回復操作・確認要求・単調時計・期限待ちを注入します。
    /// - Parameters:
    ///   - linkRecovery: 回復操作の境界。
    ///   - reader: 確認要求を送る読取部品。
    ///   - clock: 猶予を判定する単調時計。
    ///   - deadlineWaiter: 猶予切れの期限と定期試行の時刻まで待つ境界。
    init(
        linkRecovery: any LiveTelemetryLinkRecoveryPort,
        reader: OBDPIDSingleRequestReader,
        clock: any MonotonicClockPort,
        deadlineWaiter: any LiveTelemetryDeadlineWaitPort
    ) {
        self.linkRecovery = linkRecovery
        self.reader = reader
        self.clock = clock
        self.deadlineWaiter = deadlineWaiter
    }

    /// 回復段階を順に試し、使い切ったら一時停止して復帰を待ちます。
    ///
    /// 責務: 回復段階で決着しなければ、期限を過ぎていないことを確かめてから一時停止へ移ります。
    /// - Parameters:
    ///   - cause: 途切れの原因。
    ///   - grace: 最後の受信からの猶予。
    ///   - probe: 復帰の確認に送る定義。`nil` の場合は回復操作の成功だけで復帰とします。
    ///   - endpoint: 取得に使っているOBD終端。
    ///   - channel: 一時停止中の起床理由を受け取る通り道。
    ///   - linkAvailability: 一時停止に入る時点のリンク可用性を返す処理。
    ///   - report: 段階の変化を購読者へ流す処理。
    /// - Returns: 復帰した場合は新しい区間の開始理由、猶予切れの場合は `.expired`。
    /// - Throws: 取消された場合は `CancellationError`。
    func recover(
        from cause: LiveTelemetryInterruptionCause,
        grace: LiveTelemetryReceiveGrace,
        probe: OBDPIDDefinition?,
        endpoint: OBDConnectionEndpoint,
        channel: LiveTelemetryPauseWakeChannel,
        linkAvailability: @Sendable () async -> LiveTelemetryLinkAvailability,
        report: @Sendable (LiveTelemetryAcquisitionPhase) -> Void
    ) async throws -> Outcome {
        var grace = grace
        if let outcome = try await runStages(after: cause, grace: &grace, probe: probe, endpoint: endpoint, report: report) {
            return outcome
        }
        let pausedAt = clock.nowNanoseconds()
        guard !grace.isExpired(nowNanoseconds: pausedAt) else { return .expired }
        let window = LiveTelemetryPauseWindow(pausedAtNanoseconds: pausedAt, grace: grace)
        let entryReason = wakeEvaluator.entryReason(for: cause, linkAvailability: await linkAvailability())
        return try await pause(
            after: cause,
            window: window,
            entryReason: entryReason,
            probe: probe,
            endpoint: endpoint,
            channel: channel,
            report: report
        )
    }

    /// 回復段階を順に試します。
    ///
    /// 責務: 各試行の前に期限を確かめ、過ぎていれば試行せずに猶予切れとし、成功したら確定時点の経過で復帰か猶予切れかを決めます。
    /// - Parameters:
    ///   - cause: 途切れの原因。
    ///   - grace: 最後の受信からの猶予。車両応答なしと分かった場合は縮めた状態へ更新します。
    ///   - probe: 復帰の確認に送る定義。
    ///   - endpoint: 取得に使っているOBD終端。
    ///   - report: 段階の変化を購読者へ流す処理。
    /// - Returns: 復帰または猶予切れで決着した結果。段階を使い切った場合は `nil`。
    /// - Throws: 取消された場合は `CancellationError`。
    private func runStages(
        after cause: LiveTelemetryInterruptionCause,
        grace: inout LiveTelemetryReceiveGrace,
        probe: OBDPIDDefinition?,
        endpoint: OBDConnectionEndpoint,
        report: @Sendable (LiveTelemetryAcquisitionPhase) -> Void
    ) async throws -> Outcome? {
        var progress = LiveTelemetryRecoveryProgress()
        while true {
            try Task.checkCancellation()
            guard !grace.isExpired(nowNanoseconds: clock.nowNanoseconds()) else { return .expired }
            report(.recovering(cause: cause, stage: progress.stage, attempt: progress.attempt))
            let result = try await attempt(progress.stage, probe: probe, endpoint: endpoint)
            if result == .resumed { return outcomeOfSuccess(within: grace) }
            if result.isVehicleOffEvidence(for: cause) { grace.suspectVehicleOff() }
            if progress.recordFailure() == .enterGracePeriod { return nil }
        }
    }

    /// 復帰の試行が成功した時点で、猶予内かどうかから結果を決めます。
    ///
    /// 責務: 成功が確定した時点の単調時計で最後の受信からの経過を判定し、猶予内なら復帰、超えていれば猶予切れを返します。
    /// - Parameter grace: 最後の受信からの猶予。
    /// - Returns: 猶予内(ちょうど3分を含む)なら `.resumed(.reconnected)`、超えたら `.expired`。
    private func outcomeOfSuccess(within grace: LiveTelemetryReceiveGrace) -> Outcome {
        grace.isExpired(nowNanoseconds: clock.nowNanoseconds()) ? .expired : .resumed(.reconnected)
    }

    /// 一時停止に入り、猶予内の復帰の機会を待ちます。
    ///
    /// 責務: 起床理由ごとに猶予を判定し、復帰の機会(通知・定期試行の時刻)には回復を1回試し、待ちが早く返れば待ち直します。
    /// 試行の後は契機にかかわらず次の定期試行を1間隔後に予定し、回復操作がすぐ失敗しても間隔を空けます。
    /// 入った時点の起床理由があれば、通り道を開いた直後に最初の理由として処理させます。
    /// - Parameters:
    ///   - cause: 途切れの原因。
    ///   - window: 一時停止の開始時点(定期試行の起点)と最後の受信からの猶予。
    ///   - entryReason: 一時停止に入った時点で処理させる起床理由。無ければ `nil`。
    ///   - probe: 復帰の確認に送る定義。
    ///   - endpoint: 取得に使っているOBD終端。
    ///   - channel: 一時停止中の起床理由を受け取る通り道。
    ///   - report: 段階の変化を購読者へ流す処理。
    /// - Returns: 復帰した場合は新しい区間の開始理由、猶予切れの場合は `.expired`。
    /// - Throws: 取消された場合は `CancellationError`。
    private func pause(
        after cause: LiveTelemetryInterruptionCause,
        window initialWindow: LiveTelemetryPauseWindow,
        entryReason: LiveTelemetryPauseWakeReason?,
        probe: OBDPIDDefinition?,
        endpoint: OBDConnectionEndpoint,
        channel: LiveTelemetryPauseWakeChannel,
        report: @Sendable (LiveTelemetryAcquisitionPhase) -> Void
    ) async throws -> Outcome {
        var window = initialWindow
        let reasons = channel.open()
        defer { channel.close() }
        report(.paused(cause: cause))
        if let entryReason { channel.send(entryReason) }
        var deadline = arm(.deadlineReached, until: window.deadlineNanoseconds, channel: channel)
        var retry = arm(.retryDue, until: window.nextRetryNanoseconds, channel: channel)
        defer {
            deadline.cancel()
            retry.cancel()
        }
        for await reason in reasons {
            switch wakeEvaluator.action(for: reason, window: window, nowNanoseconds: clock.nowNanoseconds(), cause: cause) {
            case .terminate:
                return .expired
            case .rearmDeadline:
                deadline.cancel()
                deadline = arm(.deadlineReached, until: window.deadlineNanoseconds, channel: channel)
            case .rearmRetry:
                retry.cancel()
                retry = arm(.retryDue, until: window.nextRetryNanoseconds, channel: channel)
            case .keepWaiting:
                continue
            case let .attemptResume(stage):
                retry.cancel()
                if let outcome = try await resumeAttempt(stage, cause: cause, window: &window, probe: probe, endpoint: endpoint) {
                    return outcome
                }
                deadline.cancel()
                deadline = arm(.deadlineReached, until: window.deadlineNanoseconds, channel: channel)
                retry = arm(.retryDue, until: window.nextRetryNanoseconds, channel: channel)
            }
        }
        throw CancellationError()
    }

    /// 一時停止中の復帰の試行を1回行い、決着したか、次の試行へ進むかを決めます。
    ///
    /// 責務: 成功なら成功の確定時点の経過で結果を決め、車両応答なしと分かったら猶予を縮めて期限を判定し、
    /// 決着しなければ次の定期試行を1間隔後に予定します。
    /// - Parameters:
    ///   - stage: 試す回復段階。
    ///   - cause: 一時停止に入った途切れの原因。
    ///   - window: 猶予と定期試行の予定。車両応答なしと分かった場合は猶予を縮め、次の試行時刻を更新します。
    ///   - probe: 復帰の確認に送る定義。
    ///   - endpoint: 取得に使っているOBD終端。
    /// - Returns: 復帰または猶予切れで決着した結果。決着しなければ `nil`。
    /// - Throws: 取消された場合は `CancellationError`。
    private func resumeAttempt(
        _ stage: AcquisitionRecoveryStage,
        cause: LiveTelemetryInterruptionCause,
        window: inout LiveTelemetryPauseWindow,
        probe: OBDPIDDefinition?,
        endpoint: OBDConnectionEndpoint
    ) async throws -> Outcome? {
        let result = try await attempt(stage, probe: probe, endpoint: endpoint)
        if result == .resumed { return outcomeOfSuccess(within: window.grace) }
        if result.isVehicleOffEvidence(for: cause) {
            window.suspectVehicleOff()
            if window.decision(nowNanoseconds: clock.nowNanoseconds()) == .terminate { return .expired }
        }
        window.scheduleNextRetry(afterAttemptEndedAt: clock.nowNanoseconds())
        return nil
    }

    /// 猶予切れの期限、または次の定期試行の時刻までの待ちを始めます。
    ///
    /// 責務: 待ちが返ったら指定の起床理由を通り道へ送ります。取消された場合は送りません。
    /// - Parameters:
    ///   - reason: 待ちが返ったときに送る起床理由(`.deadlineReached` または `.retryDue`)。
    ///   - deadlineNanoseconds: 待ち終える単調時計の値。
    ///   - channel: 起床理由を送る通り道。
    /// - Returns: 待ちのTask。
    private func arm(
        _ reason: LiveTelemetryPauseWakeReason,
        until deadlineNanoseconds: UInt64,
        channel: LiveTelemetryPauseWakeChannel
    ) -> Task<Void, Never> {
        let waiter = deadlineWaiter
        return Task {
            do {
                try await waiter.wait(untilNanoseconds: deadlineNanoseconds)
            } catch is CancellationError {
                return
            } catch {
                // 期限待ち自体が失敗した場合も、判定は単調時計で行うため起床させて判定し直させます。
            }
            guard !Task.isCancelled else { return }
            channel.send(reason)
        }
    }

    /// 回復段階を1回試し、続けて確認要求で車両の応答を確かめます。
    ///
    /// 責務: 回復操作の失敗とその後の無応答を試行の失敗として返し、取消だけは送出します。
    /// - Parameters:
    ///   - stage: 試す回復段階。
    ///   - probe: 復帰の確認に送る定義。
    ///   - endpoint: 取得に使っているOBD終端。
    /// - Returns: 回復操作が成功し確認要求に正応答があれば `.resumed`、回復操作が失敗すれば `.adapterFailed`、
    ///   回復操作は成功したが確認要求が正応答にならなければ `.vehicleSilent`。
    /// - Throws: 取消された場合は `CancellationError`。
    private func attempt(
        _ stage: AcquisitionRecoveryStage,
        probe: OBDPIDDefinition?,
        endpoint: OBDConnectionEndpoint
    ) async throws -> LiveTelemetryRecoveryAttempt {
        do {
            try await perform(stage, using: endpoint)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            return .adapterFailed
        }
        try Task.checkCancellation()
        guard let probe else { return .resumed }
        let outcome = await reader.read(probe, using: endpoint)
        if outcome == .cancelled { throw CancellationError() }
        try Task.checkCancellation()
        if case .responded = outcome { return .resumed }
        return .vehicleSilent
    }

    /// 回復段階に対応する回復操作を実行します。
    ///
    /// 責務: 段階を回復操作の境界の3操作へ振り分けます。
    /// - Parameters:
    ///   - stage: 実行する回復段階。
    ///   - endpoint: 取得に使っているOBD終端。
    /// - Throws: 回復操作の失敗、または取消。
    private func perform(_ stage: AcquisitionRecoveryStage, using endpoint: OBDConnectionEndpoint) async throws {
        switch stage {
        case .promptResync: try await linkRecovery.promptResync(using: endpoint)
        case .reinitializeFromReset: try await linkRecovery.reinitializeFromReset(using: endpoint)
        case .reconnectLink: try await linkRecovery.reconnectLink(using: endpoint)
        }
    }
}
