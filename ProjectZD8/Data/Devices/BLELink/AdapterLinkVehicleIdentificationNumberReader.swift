import Foundation

/// 常駐リンク上の初期化済みアダプター越しに、モード09 PID02(`0902`)でVINを読み取ります。
///
/// 送るコマンド: `0902`(待機上限は `AdapterLinkELMCommandTimeouts.vehicleIdentificationNumber`)。
@MainActor
final class AdapterLinkVehicleIdentificationNumberReader: VehicleIdentificationNumberReadingPort {
    /// 常駐リンクの受信を引き受けるバイトストリームです。
    private let stream: AdapterLinkByteStream
    /// モード09応答を解析する既存パーサーです。
    private let parser = ELM327VehicleIdentifierParser()
    /// VINの書式判定です。
    private let format = VehicleIdentificationNumberFormat()

    /// バイトストリームを固定して生成します。
    ///
    /// 責務: VIN読取の送受信先を1本の常駐リンクへ結び付けます。
    /// - Parameter stream: 常駐リンクの受信を引き受けるバイトストリーム。
    init(stream: AdapterLinkByteStream) {
        self.stream = stream
    }

    /// 車両のVINを読み取ります。
    ///
    /// 責務: `0902` を1回問い合わせ、応答をVINへ変換します。
    /// - Returns: 書式を満たすVIN。車両が返さない(`NO DATA` 等)・解析できない・VIN書式でない場合は `nil`。
    /// - Throws: 占有・送受信の `AdapterLinkByteStreamError`(期限切れを含む)、文字列化できない応答、キャンセル。
    func readVehicleIdentificationNumber() async throws -> String? {
        let response = try await AdapterLinkELMCommandSession.perform(on: stream) { session in
            try await session.execute(
                ELM327Command.vehicleIdentificationNumber,
                timeout: AdapterLinkELMCommandTimeouts.vehicleIdentificationNumber
            )
        }
        return vehicleIdentificationNumber(in: response)
    }

    /// 応答からVINを取り出します。
    ///
    /// 責務: 既存パーサーで解析し、VIN候補が書式を満たす場合だけ返します。解析できない応答はVIN無しとして扱います。
    /// - Parameter response: `0902` の加工前応答。
    /// - Returns: 書式を満たすVIN、または `nil`。
    func vehicleIdentificationNumber(in response: String) -> String? {
        guard let vin = (try? parser.parse(response))?.vin, format.isValid(vin) else { return nil }
        return vin
    }
}
