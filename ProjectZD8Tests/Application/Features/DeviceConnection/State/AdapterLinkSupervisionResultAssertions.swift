import XCTest
@testable import ProjectZD8

/// 常駐リンク監視の遷移結果を仕様の観点で比べる検証手段です。
///
/// 仕様が順序を定めない作用は順序を問わずに比べます。取り消し・通知準備を含むすべての作用を比べます。
@MainActor
enum AdapterLinkSupervisionResultAssertions {
    /// 状態が変わらず、作用が1件もないことを検証します。
    ///
    /// 責務: 「無視されるイベント」の結果が入力状態のままで作用が空であることを確認します。
    /// - Parameters:
    ///   - result: 検証する遷移結果。
    ///   - state: 入力した状態。
    ///   - message: 失敗時に添える説明。
    static func assertIgnored(
        _ result: AdapterLinkSupervisionTransitionResult,
        from state: AdapterLinkSupervisionState,
        _ message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(result.state, state, "状態が変わった: \(message)", file: file, line: line)
        XCTAssertEqual(result.effects, [], "作用が空でない: \(message)", file: file, line: line)
    }

    /// 状態と作用の組(順序不問)を検証します。
    ///
    /// 責務: 次の状態の一致と、取り消し・通知準備を含む全作用の多重集合の一致を確認します。
    /// - Parameters:
    ///   - result: 検証する遷移結果。
    ///   - state: 期待する次の状態。
    ///   - effects: 期待する作用(取り消し・通知準備を含む全作用。順序は問わない)。
    ///   - message: 失敗時に添える説明。
    static func assertResult(
        _ result: AdapterLinkSupervisionTransitionResult,
        state: AdapterLinkSupervisionState,
        effects: [AdapterLinkSupervisionEffect],
        _ message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(result.state, state, "次の状態: \(message)", file: file, line: line)
        let actual = result.effects
        XCTAssertEqual(actual.count, effects.count, "作用の件数: \(actual) \(message)", file: file, line: line)
        for effect in effects {
            XCTAssertEqual(
                actual.filter { $0 == effect }.count,
                effects.filter { $0 == effect }.count,
                "作用 \(effect) の件数: \(actual) \(message)",
                file: file,
                line: line
            )
        }
    }
}
