import Foundation

/// 最後に正応答を受信した時刻を保持し、取得が途切れたかを判定します。
///
/// 応答途絶は単調時計の経過で `AcquisitionStallPolicy` に判定させます。通信境界の喪失(`transportFailure`)は
/// 経過を待たずに途切れとします。すぐ失敗するトランスポートで要求を空回りさせないためです。
nonisolated struct LiveTelemetryReceiveTracker: Equatable, Sendable {
    /// 最後に正応答を受信した(または区間を開始した)時点の単調時計の値です。
    private(set) var lastReceivedNanoseconds: UInt64
    /// 最後に正応答を受信した(または区間を開始した)実時間です。欠損の開始と猶予切れの終了時刻に使います。
    private(set) var lastReceivedAt: Date
    /// 最後の正応答の後に通信境界の喪失を観測したかどうかです。
    private(set) var observedLinkLoss = false

    /// 区間の開始時点を最後の受信とみなして追跡を始めます。
    ///
    /// 責務: 途絶判定の起点を区間の開始時点へ固定します。
    /// - Parameters:
    ///   - startedNanoseconds: 区間を開始した時点の単調時計の値。
    ///   - startedAt: 区間を開始した実時間。
    init(startedNanoseconds: UInt64, startedAt: Date) {
        lastReceivedNanoseconds = startedNanoseconds
        lastReceivedAt = startedAt
    }

    /// 要求1件の結果を追跡へ反映します。
    ///
    /// 責務: 正応答なら最後の受信を更新して喪失の観測を消し、通信失敗なら喪失を記録します。
    /// - Parameters:
    ///   - outcome: 要求1件のTransport観測。
    ///   - nanoseconds: 結果を受けた時点の単調時計の値。
    ///   - date: 結果を受けた実時間。
    mutating func observe(_ outcome: OBDPIDRequestTransportOutcome, atNanoseconds nanoseconds: UInt64, at date: Date) {
        switch outcome {
        case .responded:
            lastReceivedNanoseconds = max(nanoseconds, lastReceivedNanoseconds)
            lastReceivedAt = max(date, lastReceivedAt)
            observedLinkLoss = false
        case .transportFailure:
            observedLinkLoss = true
        case .unsupported, .timedOut, .unclassifiedResponse, .cancelled:
            break
        }
    }

    /// 現在の時点で取得が途切れているかを返します。
    ///
    /// 責務: 通信境界の喪失を優先し、次に最後の受信からの単調時計の経過で途絶を判定します。
    /// - Parameter nowNanoseconds: 単調時計の現在値。最後の受信より小さい場合は経過0とします。
    /// - Returns: 途切れの原因。続けられる場合は `nil`。
    func interruption(nowNanoseconds: UInt64) -> LiveTelemetryInterruptionCause? {
        if observedLinkLoss { return .linkLost }
        let elapsed = nowNanoseconds >= lastReceivedNanoseconds ? nowNanoseconds - lastReceivedNanoseconds : 0
        return AcquisitionStallPolicy().isStalled(elapsedSinceLastReceiveNanoseconds: elapsed) ? .responseStall : nil
    }

    /// 復帰した新しい区間の開始時点から追跡をやり直します。
    ///
    /// 責務: 途絶判定の起点を新しい区間の開始時点へ移し、喪失の観測を消します。
    /// - Parameters:
    ///   - nanoseconds: 新しい区間を開始した時点の単調時計の値。
    ///   - date: 新しい区間を開始した実時間。
    mutating func restart(atNanoseconds nanoseconds: UInt64, at date: Date) {
        lastReceivedNanoseconds = nanoseconds
        lastReceivedAt = date
        observedLinkLoss = false
    }
}
