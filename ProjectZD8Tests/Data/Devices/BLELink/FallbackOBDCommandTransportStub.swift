import Foundation
@testable import ProjectZD8

/// トランスポート選択で「従来のトランスポート」として返される目印の stub です。
///
/// 選択結果が同一インスタンスかどうかだけを見るため、送受信はすべて失敗させます。
final class FallbackOBDCommandTransportStub: OBDCommandTransport {
    /// 何もしない stub を生成します。
    ///
    /// 責務: 同一性の比較に使う目印のインスタンスを用意します。
    init() {}

    /// 開くことはできません。
    ///
    /// 責務: 目印として返されるだけで、使われたら失敗させます。
    func open() async throws {
        throw VehicleIdentificationError.unavailable
    }

    /// 書き込むことはできません。
    ///
    /// 責務: 目印として返されるだけで、使われたら失敗させます。
    /// - Parameter data: 送信するバイト列。
    func write(_ data: Data) async throws {
        throw VehicleIdentificationError.unavailable
    }

    /// 読み取ることはできません。
    ///
    /// 責務: 目印として返されるだけで、使われたら失敗させます。
    /// - Returns: 返しません。
    func readUntilPrompt() async throws -> Data {
        throw VehicleIdentificationError.unavailable
    }

    /// 何もしません。
    ///
    /// 責務: 閉じる対象が無いので何も行いません。
    func close() async {}
}
