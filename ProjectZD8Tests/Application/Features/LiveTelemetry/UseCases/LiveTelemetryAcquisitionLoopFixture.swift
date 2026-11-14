import Foundation
@testable import ProjectZD8

/// 取得ループと、要求を待たせるフェイク・記録ポートのスパイ・手動時計をまとめたテスト部品です。
@MainActor
final class LiveTelemetryAcquisitionLoopFixture {
    /// 表示用観測とbatch開始に付く固定日時です。
    static let fixedNow = Date(timeIntervalSince1970: 1_000)

    /// 要求を記録して応答を待たせるPID取得境界です。
    let telemetry = GatedOBDPIDTelemetryFake()
    /// 記録ポートのスパイです。記録しない経路では `nil` です。
    let recorder: LiveTelemetryRecordingPortSpy?
    /// 要求ごとの経過を測る手動時計です。
    let clock = ManualMonotonicClock()
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
        loop = LiveTelemetryAcquisitionLoop(
            telemetry: telemetry,
            recorder: recorder,
            now: { LiveTelemetryAcquisitionLoopFixture.fixedNow },
            clock: clock
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

    /// 動いている世代を止め、購読をやめます。
    ///
    /// 責務: テスト終了時に応答待ちの要求を取消で解放し、取得Taskを残さないようにします。
    func tearDown() async {
        _ = await loop.stop()
        collectors.forEach { $0.cancel() }
    }
}
