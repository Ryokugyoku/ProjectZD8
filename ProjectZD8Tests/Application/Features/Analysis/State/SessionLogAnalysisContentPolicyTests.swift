import Foundation
import XCTest
@testable import ProjectZD8

/// 解析画面が読込段階と時系列の有無から本文を選ぶ規則を検証します。
@MainActor
final class SessionLogAnalysisContentPolicyTests: XCTestCase {
    /// 検証対象の本文選択です。
    private let policy = SessionLogAnalysisContentPolicy()

    /// ダウンロード中は時系列の有無に関わらず取得率の表示です。
    ///
    /// 責務: downloading が最優先で、取得率がそのまま渡ることを確認します。
    func testDownloadingShowsProgressRegardlessOfTimeline() {
        for hasTimeline in [false, true] {
            let state = makeState(.downloading, hasTimeline: hasTimeline, progress: 0.4)

            XCTAssertEqual(policy.content(for: state), .downloading(progress: 0.4))
        }
    }

    /// 取得率が未設定なら 0 として扱います。
    ///
    /// 責務: downloadProgress が nil のときに 0 になることを確認します。
    func testDownloadingWithoutProgressUsesZero() {
        XCTAssertEqual(policy.content(for: makeState(.downloading, hasTimeline: false)), .downloading(progress: 0))
    }

    /// 取得率の境界値(0 と 1)はそのまま渡ります。
    ///
    /// 責務: 範囲の両端を補正しないことを確認します。
    func testDownloadingKeepsBoundaryProgress() {
        XCTAssertEqual(policy.content(for: makeState(.downloading, hasTimeline: false, progress: 0)), .downloading(progress: 0))
        XCTAssertEqual(policy.content(for: makeState(.downloading, hasTimeline: false, progress: 1)), .downloading(progress: 1))
    }

    /// 読込中は、時系列が空なら初回読込、あれば進捗つきの結果です。
    ///
    /// 責務: loading の2分岐を確認します。
    func testLoadingBranches() {
        XCTAssertEqual(policy.content(for: makeState(.loading, hasTimeline: false)), .initialLoading)
        XCTAssertEqual(policy.content(for: makeState(.loading, hasTimeline: true)), .results(showsProgress: true))
    }

    /// 失敗は、時系列が空なら失敗表示、あれば結果を残します。
    ///
    /// 責務: failed の2分岐を確認します(データがあれば成功扱いにも空扱いにもしない)。
    func testFailedBranches() {
        XCTAssertEqual(policy.content(for: makeState(.failed, hasTimeline: false)), .failedWithoutData)
        XCTAssertEqual(policy.content(for: makeState(.failed, hasTimeline: true)), .results(showsProgress: false))
    }

    /// 読込完了は、時系列が空なら空表示、あれば結果です。
    ///
    /// 責務: loaded の2分岐を確認します。
    func testLoadedBranches() {
        XCTAssertEqual(policy.content(for: makeState(.loaded, hasTimeline: false)), .empty)
        XCTAssertEqual(policy.content(for: makeState(.loaded, hasTimeline: true)), .results(showsProgress: false))
    }

    /// 未選択と取得確認待ちは、時系列の有無に関わらず進捗なしの結果です。
    ///
    /// 責務: 従来の if 連鎖の else に落ちる2段階を確認します。
    func testIdleAndAwaitingConfirmationShowResultsWithoutProgress() {
        for phase in [SessionLogAnalysisState.Phase.idle, .awaitingDownloadConfirmation] {
            for hasTimeline in [false, true] {
                XCTAssertEqual(
                    policy.content(for: makeState(phase, hasTimeline: hasTimeline)),
                    .results(showsProgress: false)
                )
            }
        }
    }

    /// 検証用の状態を作ります。
    ///
    /// 責務: 段階・時系列の有無・取得率を指定した解析状態を返します。
    /// - Parameters:
    ///   - phase: 読込段階。
    ///   - hasTimeline: 時系列サンプルを1件持つか。
    ///   - progress: iCloud取得率。
    /// - Returns: 検証用の解析状態。
    private func makeState(
        _ phase: SessionLogAnalysisState.Phase,
        hasTimeline: Bool,
        progress: Double? = nil
    ) -> SessionLogAnalysisState {
        var state = SessionLogAnalysisState()
        state.phase = phase
        state.downloadProgress = progress
        if hasTimeline {
            state.timeline = [SessionLogAnalysisState.TimelineSample(
                sequence: 0, observedAt: Date(timeIntervalSince1970: 0), service: 0x01, pid: 0x0C,
                nameKey: nil, value: 1, unit: nil, payload: [], decodingFailure: nil
            )]
        }
        return state
    }
}
