import Foundation
@testable import ProjectZD8

/// 監視の時計の fake です。現在時刻はテストが進め、待機はテストが `finishOldestSleep` で終わらせるまで保留します。
@MainActor
final class AdapterLinkSupervisionClockFake: AdapterLinkSupervisionClock {
    /// 現在時刻です。テストが直接進めます。
    var now: Date

    /// 待機の保留中の呼び出しです。
    let sleeps = AdapterLinkSupervisionScriptedResponses<Void>()

    /// 待機に渡された時間です(呼び出し順)。
    private(set) var requestedDurations: [Duration] = []

    /// 開始時刻を指定して生成します。
    ///
    /// 責務: テスト開始時の現在時刻を固定します。
    /// - Parameter now: 開始時刻。
    init(now: Date) {
        self.now = now
    }

    /// 待機を記録し、テストが終わらせるまで保留します。
    ///
    /// 責務: 待機時間を記録して、後渡しの結果で戻ります。
    /// - Parameter duration: 待機する時間。
    func sleep(for duration: Duration) async throws {
        requestedDurations.append(duration)
        try await sleeps.next()
    }

    /// 最も古い待機を、現在時刻を指定秒数進めてから終わらせます。
    ///
    /// 責務: 時刻の経過と待機の完了を1回分まとめて起こします。
    /// - Parameter seconds: 進める秒数。
    /// - Returns: 待機を終わらせられた場合は `true`。保留中の待機が無かった場合は `false`(XCTFail 済み)。
    @discardableResult
    func finishOldestSleep(advancingBy seconds: TimeInterval, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        now = now.addingTimeInterval(seconds)
        return sleeps.resumeOldest(with: .success(()), file: file, line: line)
    }
}
