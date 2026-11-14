import Foundation
@testable import ProjectZD8

/// 回復操作の呼び出しを順に記録し、予約した結果(成功・失敗)を返す回復ポートのフェイクです。
///
/// 予約が尽きたら失敗(`.rejected`)を返します。実時間では待ちません。
@MainActor
final class LinkRecoveryPortFake: LiveTelemetryLinkRecoveryPort {
    /// 呼ばれた回復段階です。呼ばれた順に並びます。
    private(set) var calls: [AcquisitionRecoveryStage] = []
    /// 次の呼び出しから順に返す結果です。`true` は成功です。
    private var scheduledResults: [Bool] = []

    /// 予約なしで生成します。
    ///
    /// 責務: すべての呼び出しが失敗するフェイクを構築します。
    init() {}

    /// 次の呼び出しから順に返す結果を予約します。
    ///
    /// 責務: 予約済みの結果の後ろへ追加します。
    /// - Parameter results: 返す結果。`true` は成功です。
    func schedule(_ results: [Bool]) {
        scheduledResults += results
    }

    /// プロンプト再同期を記録します。
    ///
    /// 責務: 呼び出しを記録し、予約した結果を返します。
    /// - Parameter endpoint: 使用するOBD終端。
    /// - Throws: 失敗を返す場合は `.rejected`。
    func promptResync(using endpoint: OBDConnectionEndpoint) async throws {
        try perform(.promptResync)
    }

    /// ATZ再初期化を記録します。
    ///
    /// 責務: 呼び出しを記録し、予約した結果を返します。
    /// - Parameter endpoint: 使用するOBD終端。
    /// - Throws: 失敗を返す場合は `.rejected`。
    func reinitializeFromReset(using endpoint: OBDConnectionEndpoint) async throws {
        try perform(.reinitializeFromReset)
    }

    /// 再接続を記録します。
    ///
    /// 責務: 呼び出しを記録し、予約した結果を返します。
    /// - Parameter endpoint: 使用するOBD終端。
    /// - Throws: 失敗を返す場合は `.rejected`。
    func reconnectLink(using endpoint: OBDConnectionEndpoint) async throws {
        try perform(.reconnectLink)
    }

    /// 回復段階の呼び出しが指定件数に達するまで上限付きで待ちます。
    ///
    /// 責務: 呼び出し件数の到達を待ち、上限を超えたら失敗させます。
    /// - Parameters:
    ///   - count: 待つ呼び出し件数。
    ///   - file: 失敗を報告するファイル。
    ///   - line: 失敗を報告する行。
    /// - Returns: 到達した場合は `true`。
    @discardableResult
    func waitForCalls(_ count: Int, file: StaticString = #filePath, line: UInt = #line) async -> Bool {
        await LiveTelemetryBoundedWaiter.waitUntil("回復操作 \(count) 件", file: file, line: line) {
            self.calls.count >= count
        }
    }

    /// 呼び出しを記録して予約した結果を返します。
    ///
    /// 責務: 予約の先頭を消費し、失敗なら `.rejected` を送出します。
    /// - Parameter stage: 呼ばれた回復段階。
    /// - Throws: 失敗を返す場合は `.rejected`。
    private func perform(_ stage: AcquisitionRecoveryStage) throws {
        calls.append(stage)
        let succeeds = scheduledResults.isEmpty ? false : scheduledResults.removeFirst()
        if !succeeds { throw LiveTelemetryLinkRecoveryError.rejected }
    }
}
