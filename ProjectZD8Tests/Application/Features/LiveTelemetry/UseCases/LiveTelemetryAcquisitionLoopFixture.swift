import Foundation
@testable import ProjectZD8

/// 取得ループと、要求を待たせるフェイク・記録ポートのスパイ・回復ポートのフェイク・期限待ちのフェイク・手動時計をまとめたテスト部品です。
@MainActor
final class LiveTelemetryAcquisitionLoopFixture {
    /// 実時刻clockの初期日時です。
    static let fixedNow = Date(timeIntervalSince1970: 1_000)

    /// 要求を記録して応答を待たせるPID取得境界です。
    let telemetry = GatedOBDPIDTelemetryFake()
    /// 記録ポートのスパイです。記録しない経路では `nil` です。
    let recorder: LiveTelemetryRecordingPortSpy?
    /// 要求ごとの経過・途絶・猶予を測る手動の単調時計です。
    let clock = ManualMonotonicClock()
    /// batch開始・観測・最後の受信に付く手動の実時刻clockです。
    let dates = ManualDateClock(LiveTelemetryAcquisitionLoopFixture.fixedNow)
    /// 回復操作を記録して予約した結果を返すフェイクです。
    let linkRecovery = LinkRecoveryPortFake()
    /// 一時停止中の期限待ちをテストが解放するまで待たせるフェイクです。
    let deadlineWaiter = ControlledDeadlineWaiterFake()
    /// 検証対象の取得ループです。
    let loop: LiveTelemetryAcquisitionLoop
    /// 開始した世代の購読です。
    private var collectors: [LiveTelemetryAcquisitionEventCollector] = []

    /// 記録ポートの有無と失敗指定を固定して生成します。
    ///
    /// 責務: フェイク・スパイ・時計を取得ループへ注入します。
    /// - Parameter recorder: 記録ポートのスパイ。`nil` なら記録しない経路にします。
    init(recorder: LiveTelemetryRecordingPortSpy? = LiveTelemetryRecordingPortSpy()) {
        self.recorder = recorder
        let dates = dates
        loop = LiveTelemetryAcquisitionLoop(
            telemetry: telemetry,
            recorder: recorder,
            now: { dates.now() },
            clock: clock,
            linkRecovery: linkRecovery,
            deadlineWaiter: deadlineWaiter
        )
    }

    /// 1世代の取得を始め、その出来事の購読を返します。
    ///
    /// 責務: 取得対象と既定のcapabilityでループを開始し、購読を後片付けの対象に加えます。
    /// - Parameters:
    ///   - generation: 世代。
    ///   - definitions: 取得対象の定義。
    ///   - capabilities: 定義ごとのcapability。`nil` なら定義と同数の収集有効capability。
    /// - Returns: 出来事の購読。
    func start(
        generation: UInt = 1,
        definitions: [OBDPIDDefinition],
        capabilities: [ConnectionSessionAcquisitionPIDCapabilityInput]? = nil
    ) async -> LiveTelemetryAcquisitionEventCollector {
        let input = LiveTelemetryAcquisitionLoopInput(
            generation: generation,
            definitions: definitions,
            capabilities: capabilities ?? LiveTelemetryTestDefinitions.capabilities(for: definitions),
            endpoint: LiveTelemetryTestDefinitions.endpoint
        )
        let collector = LiveTelemetryAcquisitionEventCollector(await loop.start(input))
        collectors.append(collector)
        return collector
    }

    /// 送信済み要求が指定件数に達するまで上限付きで待ちます。
    ///
    /// 責務: 送信件数の到達を待ち、上限を超えたら失敗させます。
    /// - Parameters:
    ///   - count: 待つ送信件数。
    ///   - file: 失敗を報告するファイル。
    ///   - line: 失敗を報告する行。
    /// - Returns: 到達した場合は `true`。
    @discardableResult
    func waitForSentRequests(_ count: Int, file: StaticString = #filePath, line: UInt = #line) async -> Bool {
        await telemetry.waitForSentRequests(count, file: file, line: line)
    }

    /// 購読が終了理由を受けるまで上限付きで待ちます。
    ///
    /// 責務: 終了理由の到着とストリームの終了を待ち、上限を超えたら失敗させます。
    /// - Parameters:
    ///   - collector: 待つ購読。
    ///   - file: 失敗を報告するファイル。
    ///   - line: 失敗を報告する行。
    /// - Returns: 受けた終了理由。上限を超えた場合は `nil`。
    func waitForTermination(
        of collector: LiveTelemetryAcquisitionEventCollector,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> LiveTelemetryAcquisitionTermination? {
        await LiveTelemetryBoundedWaiter.waitUntil("取得ループの終了", file: file, line: line) {
            collector.isFinished
        }
        return collector.termination
    }

    /// 取得ループを止め、上限内に終われば終了理由を返します。
    ///
    /// 責務: `stop` の完了を上限付きで待ち、実装が止まらなくてもテストが待ち続けないようにします。
    /// - Parameters:
    ///   - file: 失敗を報告するファイル。
    ///   - line: 失敗を報告する行。
    /// - Returns: `stop` の結果。上限を超えた場合(失敗済み)と、動いていなかった場合は `nil`。
    func stopLoop(file: StaticString = #filePath, line: UInt = #line) async -> LiveTelemetryAcquisitionTermination? {
        let loop = loop
        return await LiveTelemetryBoundedWaiter.value("取得ループの停止", file: file, line: line) { await loop.stop() } ?? nil
    }

    /// 動いている世代を止め、購読をやめます。
    ///
    /// 責務: テスト終了時に応答待ちの要求と期限待ちを解放し、取得Taskを残さないようにします。
    func tearDown() async {
        _ = await stopLoop()
        deadlineWaiter.releaseAll()
        collectors.forEach { $0.cancel() }
    }

    /// PID 0x0C だけの取得を始め、正応答1件の後に途絶させて、回復を使い切った一時停止まで進めます。
    ///
    /// 責務: 回復操作をすべて失敗させ、原因に応じた途絶(通信失敗、または途絶閾値の経過後のタイムアウト)を起こします。
    /// 最後の正応答は現在の実時刻で受けます。
    /// - Parameter cause: 起こす途絶の原因。
    /// - Returns: 購読と、一時停止に入った時点の単調時計の値。
    func startAndPause(
        cause: LiveTelemetryInterruptionCause,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> (LiveTelemetryAcquisitionEventCollector, UInt64) {
        let collector = await start(definitions: [LiveTelemetryTestDefinitions.standard(0x0C)])
        await telemetry.release(.responded([1]), file: file, line: line)
        switch cause {
        case .linkLost:
            await telemetry.release(.transportFailure, file: file, line: line)
        case .responseStall:
            await telemetry.waitForSentRequests(2, file: file, line: line)
            clock.advance(byNanoseconds: AcquisitionStallPolicy.stallThresholdNanoseconds)
            await telemetry.release(.timedOut, file: file, line: line)
        }
        await waitForPause(of: collector, file: file, line: line)
        return (collector, clock.nowNanoseconds())
    }

    /// 購読が一時停止の出来事を受けるまで上限付きで待ちます。
    ///
    /// 責務: 回復を使い切って一時停止に入ったことを待ち、上限を超えたら失敗させます。
    /// - Parameters:
    ///   - collector: 待つ購読。
    ///   - file: 失敗を報告するファイル。
    ///   - line: 失敗を報告する行。
    /// - Returns: 一時停止に入った場合は `true`。
    @discardableResult
    func waitForPause(
        of collector: LiveTelemetryAcquisitionEventCollector,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> Bool {
        await LiveTelemetryBoundedWaiter.waitUntil("一時停止", file: file, line: line) {
            collector.phases.contains { if case .paused = $0 { true } else { false } }
        }
    }
}
