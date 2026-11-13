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
