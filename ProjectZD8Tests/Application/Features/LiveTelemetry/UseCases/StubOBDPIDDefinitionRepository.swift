import Foundation
@testable import ProjectZD8

/// 固定のPID定義を返し、読込失敗も指定できる定義Repositoryです。
struct StubOBDPIDDefinitionRepository: OBDPIDDefinitionRepository {
    /// 定義読込の失敗です。
    struct ReadError: Error {}

    /// 返す定義です。
    private let storedDefinitions: [OBDPIDDefinition]
    /// 読込を失敗させるかどうかです。
    private let failsRead: Bool

    /// 返す定義と失敗指定を固定します。
    ///
    /// 責務: 定義供給境界を固定値で構築します。
    /// - Parameters:
    ///   - definitions: 返す定義。
    ///   - failsRead: 読込を失敗させる場合は `true`。
    init(definitions: [OBDPIDDefinition], failsRead: Bool = false) {
        storedDefinitions = definitions
        self.failsRead = failsRead
    }

    /// 固定の定義を返します。
    ///
    /// 責務: 指定に応じて固定定義を返すか読込失敗を送出します。
    /// - Returns: 固定の定義。
    /// - Throws: 読込を失敗させる場合は `ReadError`。
    func definitions() throws -> [OBDPIDDefinition] {
        if failsRead { throw ReadError() }
        return storedDefinitions
    }

    /// 保存要求を受け付けます。
    ///
    /// 責務: テストで使わない保存を変更なしで完了します。
    /// - Parameter definition: 使わない定義。
    func upsert(_ definition: OBDPIDDefinition) throws {}

    /// 単一定義を固定定義から探します。
    ///
    /// 責務: Service/PIDが一致する固定定義を返します。
    /// - Parameters:
    ///   - service: Service番号。
    ///   - pid: PID番号。
    /// - Returns: 一致する定義。無ければ `nil`。
    func definition(service: UInt8, pid: UInt8) throws -> OBDPIDDefinition? {
        storedDefinitions.first { $0.service == service && $0.pid == pid }
    }
}
