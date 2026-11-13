import XCTest
@testable import ProjectZD8

/// アダプター接続役割の二重割当規則を検証します。
final class AdapterAssignmentPolicyTests: XCTestCase {
    /// 同じ安定識別子を別役割へ割り当てる競合を検出することを検証します。
    ///
    /// 責務: 既存プライマリー候補のセカンダリー割当が競合役割を返すことを確認します。
    func testConflictingRoleFindsSameAdapterAssignedToAnotherRole() {
        let adapter = makeAdapter(id: "shared")

        let result = AdapterAssignmentPolicy.conflictingRole(
            for: adapter,
            assigningTo: .secondary,
            assignments: [.primary: adapter]
        )

        XCTAssertEqual(result, .primary)
    }

    /// 異なる物理アダプターの割当を競合としないことを検証します。
    ///
    /// 責務: 別の安定識別子を持つ候補が新しい接続役割へ割り当て可能なことを確認します。
    func testConflictingRoleAllowsDifferentPhysicalAdapter() {
        let primary = makeAdapter(id: "primary")
        let secondary = makeAdapter(id: "secondary")

        let result = AdapterAssignmentPolicy.conflictingRole(
            for: secondary,
            assigningTo: .secondary,
            assignments: [.primary: primary]
        )

        XCTAssertNil(result)
    }

    /// 指定識別子を持つテスト用アダプター候補を生成します。
    ///
    /// 責務: Domain割当規則へ渡す最小のBluetooth候補を構築します。
    /// - Parameter id: 候補の安定識別子。
    /// - Returns: 未接続のBluetooth候補。
    private func makeAdapter(id: String) -> DiscoveredAdapter {
        DiscoveredAdapter(
            id: id,
            transportMode: .bluetooth,
            displayName: id,
            systemIdentifier: id,
            isConnected: false
        )
    }
}
