@testable import ProjectZD8

/// アダプターがTransportを作るたびに、用意したTransportを順に渡す生成元です。
@MainActor
final class OBDCommandTransportQueue {
    /// 用意したTransportです。作られる順に並びます。
    let transports: [ScriptedOBDCommandTransportFake]
    /// Transportが作られた回数です。
    private(set) var makeCount = 0

    /// 用意したTransportを固定します。
    ///
    /// 責務: 作られる順のTransportを保持します。
    /// - Parameter transports: 用意したTransport。
    init(_ transports: [ScriptedOBDCommandTransportFake]) {
        self.transports = transports
    }

    /// 次のTransportを渡します。
    ///
    /// 責務: 作られた回数を数え、用意した順にTransportを返します。用意が尽きたら接続失敗を送出します。
    /// - Returns: 次のTransport。
    /// - Throws: 用意が尽きた場合は `VehicleIdentificationError.connectionFailed`。
    func next() throws -> any OBDCommandTransport {
        defer { makeCount += 1 }
        guard makeCount < transports.count else { throw VehicleIdentificationError.connectionFailed }
        return transports[makeCount]
    }
}
