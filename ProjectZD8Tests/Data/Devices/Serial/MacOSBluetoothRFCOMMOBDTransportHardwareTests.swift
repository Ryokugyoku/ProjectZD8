#if os(macOS)
import Foundation
import XCTest
@testable import ProjectZD8

/// 明示指定された実OBDLink MX+とのRFCOMM接続とアダプター識別だけを確認します。
final class MacOSBluetoothRFCOMMOBDTransportHardwareTests: XCTestCase {
    /// 実機Bluetoothアドレスを渡した場合だけ車両バスへ触れないATI確認を実行します。
    ///
    /// 責務: ペアリング済みMX+のSPP解決、RFCOMM接続、アダプター識別応答を1回の実機証跡として検証します。
    func testPairedMXPlusRespondsToAdapterIdentityWithoutVehicleRequest() async throws {
        guard let deviceAddress = ProcessInfo.processInfo.environment["PROJECTZD8_MXPLUS_ADDRESS"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !deviceAddress.isEmpty else {
            throw XCTSkip("PROJECTZD8_MXPLUS_ADDRESSを設定した明示的な実機確認でだけ実行します。")
        }

        let transport = MacOSBluetoothRFCOMMOBDTransport(deviceAddress: deviceAddress)
        do {
            try await transport.open()
            let channel = SerializedELMCommandChannel(transport: transport)
            let response = try await channel.execute(ELM327Command.adapterIdentity)
            await transport.close()

            let normalizedResponse = response
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            XCTAssertFalse(normalizedResponse.isEmpty)
            XCTAssertFalse(normalizedResponse.contains("?"))
            XCTAssertFalse(normalizedResponse.contains("ERROR"))
        } catch {
            await transport.close()
            throw error
        }
    }
}
#endif
