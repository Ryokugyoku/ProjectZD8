/// 取得が途切れた後、回復段階を順に試し、使い切ったら一時停止して猶予内の復帰を待つ手順です。
///
/// 回復段階の進め方は `LiveTelemetryRecoveryProgress`(`AcquisitionStallPolicy`)、一時停止中の判定は
/// `LiveTelemetryPauseWakeEvaluator`(`AcquisitionGracePeriodPolicy`)に任せ、この型は副作用の順序づけだけを行います。
/// 回復操作の成功はアダプターとの通信を立て直せたことだけを表すため、続けて1件の要求(確認要求)を送り、
/// 正応答を得たときだけ復帰とします。確認要求の応答は区間が閉じている間のものなので記録しません。
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
    /// 猶予切れの期限まで待つ境界です。
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
    ///   - deadlineWaiter: 猶予切れの期限まで待つ境界。
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
    /// 責務: 段階ごとの試行と段階の変化の通知を行い、復帰または猶予切れで返ります。
    /// - Parameters:
    ///   - cause: 途切れの原因。
    ///   - probe: 復帰の確認に送る定義。`nil` の場合は回復操作の成功だけで復帰とします。
    ///   - endpoint: 取得に使っているOBD終端。
    ///   - channel: 一時停止中の起床理由を受け取る通り道。
    ///   - report: 段階の変化を購読者へ流す処理。
    /// - Returns: 復帰した場合は新しい区間の開始理由、猶予切れの場合は `.expired`。
    /// - Throws: 取消された場合は `CancellationError`。
    func recover(
        from cause: LiveTelemetryInterruptionCause,
        probe: OBDPIDDefinition?,
        endpoint: OBDConnectionEndpoint,
        channel: LiveTelemetryPauseWakeChannel,
        report: @Sendable (LiveTelemetryAcquisitionPhase) -> Void
    ) async throws -> Outcome {
        var progress = LiveTelemetryRecoveryProgress()
        while true {
            try Task.checkCancellation()
            report(.recovering(cause: cause, stage: progress.stage, attempt: progress.attempt))
            if try await attempt(progress.stage, probe: probe, endpoint: endpoint) {
                return .resumed(.reconnected)
            }
            if progress.recordFailure() == .enterGracePeriod { break }
        }
        return try await pause(after: cause, probe: probe, endpoint: endpoint, channel: channel, report: report)
    }

    /// 一時停止に入り、猶予内の復帰の機会を待ちます。
    ///
    /// 責務: 起床理由ごとに猶予を判定し、復帰の機会には回復を1回試し、期限待ちが早く返れば待ち直します。
    /// - Parameters:
    ///   - cause: 途切れの原因。
    ///   - probe: 復帰の確認に送る定義。
    ///   - endpoint: 取得に使っているOBD終端。
    ///   - channel: 一時停止中の起床理由を受け取る通り道。
    ///   - report: 段階の変化を購読者へ流す処理。
    /// - Returns: 復帰した場合は新しい区間の開始理由、猶予切れの場合は `.expired`。
    /// - Throws: 取消された場合は `CancellationError`。
    private func pause(
        after cause: LiveTelemetryInterruptionCause,
        probe: OBDPIDDefinition?,
        endpoint: OBDConnectionEndpoint,
        channel: LiveTelemetryPauseWakeChannel,
        report: @Sendable (LiveTelemetryAcquisitionPhase) -> Void
    ) async throws -> Outcome {
        let window = LiveTelemetryPauseWindow(pausedAtNanoseconds: clock.nowNanoseconds())
        let reasons = channel.open()
        defer { channel.close() }
        report(.paused(cause: cause))
        var deadline = armDeadline(window.deadlineNanoseconds, channel: channel)
        defer { deadline.cancel() }
        for await reason in reasons {
            switch wakeEvaluator.action(for: reason, window: window, nowNanoseconds: clock.nowNanoseconds(), cause: cause) {
            case .terminate:
                return .expired
            case .rearmDeadline:
                deadline.cancel()
                deadline = armDeadline(window.deadlineNanoseconds, channel: channel)
            case .keepWaiting:
                continue
            case let .attemptResume(stage):
                guard try await attempt(stage, probe: probe, endpoint: endpoint) else { continue }
                guard window.decision(nowNanoseconds: clock.nowNanoseconds()) == .continueWaiting else { return .expired }
                return .resumed(.reconnected)
            }
        }
        throw CancellationError()
    }

    /// 猶予切れの期限待ちを始めます。
    ///
    /// 責務: 期限待ちが返ったら起床理由として通り道へ送ります。取消された場合は送りません。
    /// - Parameters:
    ///   - deadlineNanoseconds: 待ち終える単調時計の値。
    ///   - channel: 起床理由を送る通り道。
    /// - Returns: 期限待ちのTask。
    private func armDeadline(_ deadlineNanoseconds: UInt64, channel: LiveTelemetryPauseWakeChannel) -> Task<Void, Never> {
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
            channel.send(.deadlineReached)
        }
    }

    /// 回復段階を1回試し、続けて確認要求で車両の応答を確かめます。
    ///
    /// 責務: 回復操作の失敗とその後の無応答を試行の失敗として返し、取消だけは送出します。
    /// - Parameters:
    ///   - stage: 試す回復段階。
    ///   - probe: 復帰の確認に送る定義。
    ///   - endpoint: 取得に使っているOBD終端。
    /// - Returns: 回復操作が成功し、確認要求に正応答があった場合は `true`。
    /// - Throws: 取消された場合は `CancellationError`。
    private func attempt(
        _ stage: AcquisitionRecoveryStage,
        probe: OBDPIDDefinition?,
        endpoint: OBDConnectionEndpoint
    ) async throws -> Bool {
        do {
            try await perform(stage, using: endpoint)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            return false
        }
        try Task.checkCancellation()
        guard let probe else { return true }
        let outcome = await reader.read(probe, using: endpoint)
        if outcome == .cancelled { throw CancellationError() }
        try Task.checkCancellation()
        if case .responded = outcome { return true }
        return false
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
