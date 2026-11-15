import Foundation

/// 常駐リンク上の初期化済みアダプター越しに、標準PID `0100` でECUの応答を確認します。
///
/// 送るコマンド列: `.standard` は `ATST32` → `0100`(待機上限10秒)、
/// `.adapterMaximum` は `ATSTFF` → `0100`(待機上限30秒)。待機上限は `AdapterLinkELMCommandTimeouts` に定義します。
/// アダプター側のタイムアウトは問い合わせのたびに設定し直し、問い合わせ後は戻しません
/// (記録開始時のテレメトリ初期化が `ATZ` で既定値へ戻すため)。
@MainActor
final class AdapterLinkVehicleResponseConfirmer: VehicleResponseConfirmationPort {
    /// 問い合わせる標準PID `0100` です(サービス01なので常に生成できます)。
    private static let supportedPIDsRequest = ELM327CurrentDataCommand(request: OBDPIDRequest(service: 0x01, pid: 0x00))
    /// `0100` の要求識別子です。
    private static let supportedPIDsRequestID = "0100"

    /// 常駐リンクの受信を引き受けるバイトストリームです。
    private let stream: AdapterLinkByteStream
    /// 応答の有無を決める分類器です。
    private let classifier = ELM327VehicleResponseClassifier()

    /// バイトストリームを固定して生成します。
    ///
    /// 責務: 車両確認の送受信先を1本の常駐リンクへ結び付けます。
    /// - Parameter stream: 常駐リンクの受信を引き受けるバイトストリーム。
    init(stream: AdapterLinkByteStream) {
        self.stream = stream
    }

    /// 指定したタイムアウトでECUの応答を確認します。
    ///
    /// 責務: アダプター側タイムアウトを設定してから `0100` を1回問い合わせ、正応答の有無を返します。
    /// - Parameter timeout: 通常のタイムアウトかアダプター側の最大タイムアウトか。
    /// - Returns: 正応答があれば `.responding`、無応答系の応答なら `.noResponse`。
    /// - Throws: 占有・送受信の `AdapterLinkByteStreamError`(ホスト側の期限切れを含む)、`ATST` の拒否、キャンセル。
    func confirmVehicleResponse(timeout: VehicleResponseTimeout) async throws -> VehicleResponseOutcome {
        let (adapterTimeout, hostTimeout) = Self.timeouts(for: timeout)
        guard let request = Self.supportedPIDsRequest else {
            throw AdapterLinkELMCommandError.commandRejected(requestID: Self.supportedPIDsRequestID)
        }
        return try await AdapterLinkELMCommandSession.perform(on: stream) { session in
            _ = try await session.executeAccepted(adapterTimeout, timeout: AdapterLinkELMCommandTimeouts.configuration)
            let response = try await session.execute(request, timeout: hostTimeout)
            return classifier.classify(response)
        }
    }

    /// タイムアウト種別をアダプター側の設定とホスト側の待機上限へ変換します。
    ///
    /// 責務: 種別ごとに送る `ATST` と、それに見合う `0100` の待機上限を返します。
    /// - Parameter timeout: タイムアウト種別。
    /// - Returns: アダプター側の設定コマンドとホスト側の待機上限。
    static func timeouts(for timeout: VehicleResponseTimeout) -> (ELM327ResponseTimeoutCommand, Duration) {
        switch timeout {
        case .standard:
            (.standard, AdapterLinkELMCommandTimeouts.standardVehicleResponse)
        case .adapterMaximum:
            (.maximum, AdapterLinkELMCommandTimeouts.adapterMaximumVehicleResponse)
        }
    }
}
