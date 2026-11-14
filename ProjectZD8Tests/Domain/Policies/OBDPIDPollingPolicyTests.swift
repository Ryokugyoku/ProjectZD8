import XCTest
@testable import ProjectZD8

/// PID更新方針の高優先周期と全件周期を検証します。
@MainActor
final class OBDPIDPollingPolicyTests: XCTestCase {
    /// 高優先tickでは回転数と車速だけを選びます。
    ///
    /// 責務: 通常tickが高優先PIDだけを読取対象にすることを確認します。
    func testNormalTickSelectsHighPriorityDefinitions() {
        let selected = OBDPIDPollingPolicy().definitionsToPoll(from: definitions, tick: 1)

        XCTAssertEqual(selected.map(\.pid), [0x0C, 0x0D])
    }

    /// 8tickごとに低優先PIDも読み直します。
    ///
    /// 責務: 全件tickが高優先PIDの後へ通常PIDを含めることを確認します。
    func testEighthTickIncludesAllSupportedDefinitions() {
        let selected = OBDPIDPollingPolicy().definitionsToPoll(from: definitions, tick: 8)

        XCTAssertEqual(selected.map(\.pid), [0x0C, 0x0D, 0x05])
    }

    /// 高優先4件は周回番号によらず毎周回選ばれます。
    ///
    /// 責務: 0x04/0x0C/0x0D/0x11が8の倍数でない周回にも含まれ、他のPIDは含まれないことを確認します。
    func testFourHighPriorityPIDsAreSelectedEveryTick() {
        let all = [0x04, 0x05, 0x0C, 0x0D, 0x0F, 0x11].map { definition(pid: $0) }
        for tick in [UInt(1), 7, 9] {
            let selected = OBDPIDPollingPolicy().definitionsToPoll(from: all, tick: tick)
            XCTAssertEqual(Set(selected.map(\.pid)), [0x04, 0x0C, 0x0D, 0x11], "tick \(tick)")
        }
    }

    /// 8の倍数の周回(0を含む)だけ他のPIDも選ばれます。
    ///
    /// 責務: 周回番号0・8・16で全件が選ばれることを確認します。
    func testMultiplesOfEightIncludeAllDefinitions() {
        let all = [0x04, 0x05, 0x0C, 0x0D, 0x0F, 0x11].map { definition(pid: $0) }
        for tick in [UInt(0), 8, 16] {
            let selected = OBDPIDPollingPolicy().definitionsToPoll(from: all, tick: tick)
            XCTAssertEqual(Set(selected.map(\.pid)), [0x04, 0x05, 0x0C, 0x0D, 0x0F, 0x11], "tick \(tick)")
        }
    }

    /// 高優先が1件も無い定義集合では毎周回すべて選ばれます。
    ///
    /// 責務: 高優先なしの集合が8の倍数でない周回にも全件選ばれることを確認します。
    func testWithoutHighPriorityAllDefinitionsAreSelectedEveryTick() {
        let others = [0x05, 0x0F].map { definition(pid: $0) }
        for tick in [UInt(0), 1, 7, 9] {
            let selected = OBDPIDPollingPolicy().definitionsToPoll(from: others, tick: tick)
            XCTAssertEqual(Set(selected.map(\.pid)), [0x05, 0x0F], "tick \(tick)")
        }
    }

    /// 優先度検証に使う3件のPID定義です。
    private var definitions: [OBDPIDDefinition] {
        [definition(pid: 0x05), definition(pid: 0x0C), definition(pid: 0x0D)]
    }

    /// 指定PIDの最小テスト定義を生成します。
    ///
    /// 責務: 1件のPID番号を優先度検証用定義へ変換します。
    /// - Parameter pid: 生成するService 01 PID番号。
    /// - Returns: 恒等式を持つテスト定義。
    private func definition(pid: UInt8) -> OBDPIDDefinition {
        OBDPIDDefinition(
            service: 0x01,
            pid: pid,
            nameKey: "test",
            requiredByteCount: 1,
            formula: "A",
            unit: "",
            minimumValue: nil,
            maximumValue: nil,
            sourceURI: "test://polling",
            revision: 1
        )
    }
}
