import Foundation

/// 常駐リンクが保持している接続の上で、ELM/STNコマンドをやり取りする `OBDCommandTransport` です。
///
/// 接続操作は行わず、`open()` は `ready` の確認と送受信の占有権の取得だけ、`close()` は占有権の解放だけを行います。
/// リンクは止めないので、`close()` 後もリンクは `ready` のままです。
/// 既存の利用側(`SerializedELMCommandChannel`、テレメトリ)がそのまま扱えるよう、失敗は `VehicleIdentificationError` で返します。
@MainActor
final class AdapterLinkOBDCommandTransport: OBDCommandTransport {
    /// 送受信を占有するバイトストリームです。
    private let stream: AdapterLinkByteStream
    /// 1件の応答のプロンプトを待つ上限です。
    private let responseTimeout: Duration
    /// `open()` で取得した占有権です。
    private var lease: AdapterLinkByteStreamLease?

    /// バイトストリームと応答待ち上限を固定して生成します。
    ///
    /// 責務: 1利用者分のトランスポートを、リンク1本につき1つのバイトストリームへ結び付けます。
    /// - Parameters:
    ///   - stream: 常駐リンクの受信を引き受けるバイトストリーム。
    ///   - responseTimeout: 1件の応答のプロンプトを待つ上限。
    init(stream: AdapterLinkByteStream, responseTimeout: Duration = AdapterLinkELMCommandTimeouts.telemetryResponse) {
        self.stream = stream
        self.responseTimeout = responseTimeout
    }

    /// 常駐リンクが `ready` であることを確認し、送受信の占有権を取得します。
    ///
    /// 責務: 接続操作をせずに、このトランスポートを送受信可能な状態にします。取得済みなら何もしません。
    /// - Throws: `ready` でない・占有権を得られない場合は `VehicleIdentificationError.connectionFailed`、キャンセル時は `CancellationError`。
    func open() async throws {
        if lease != nil { return }
        guard stream.linkState == .ready else { throw VehicleIdentificationError.connectionFailed }
        do {
            lease = try await stream.acquireLease()
        } catch {
            throw Self.translated(error)
        }
    }

    /// 1件のコマンドを常駐リンクへ書き込みます。
    ///
    /// 責務: 占有中の場合だけバイト列をリンクへ渡します。
    /// - Parameter data: 復帰文字を含む完全なASCIIコマンド。
    /// - Throws: 未オープン・`ready` でない・書き込み失敗の場合は `VehicleIdentificationError.connectionFailed`。
    func write(_ data: Data) async throws {
        guard let lease else { throw VehicleIdentificationError.connectionFailed }
        do {
            try await stream.write(data, lease: lease)
        } catch {
            throw Self.translated(error)
        }
    }

    /// 次のプロンプト `>` までの応答を返します。
    ///
    /// 責務: 分割して届いた受信を1件の応答へ結合し、上限時間で必ず終えます。
    /// - Returns: `>` を含む加工前応答バイト。
    /// - Throws: 期限切れは `VehicleIdentificationError.responseTimedOut`、未オープン・切断は `.connectionFailed`、
    ///   受信超過は `.malformedResponse`、キャンセル時は `CancellationError`。
    func readUntilPrompt() async throws -> Data {
        guard let lease else { throw VehicleIdentificationError.connectionFailed }
        do {
            return try await stream.readUntilPrompt(lease: lease, timeout: responseTimeout)
        } catch {
            throw Self.translated(error)
        }
    }

    /// 送受信の占有権を解放します。
    ///
    /// 責務: 受信バッファーと待機を後始末して占有権を手放します。リンクは止めません。
    func close() async {
        guard let lease else { return }
        self.lease = nil
        stream.release(lease)
    }

    /// バイトストリームのエラーを既存の識別エラーへ変換します。
    ///
    /// 責務: 利用側が判別できる `VehicleIdentificationError` へ写し、キャンセルなど他の型はそのまま返します。
    /// - Parameter error: バイトストリームが返したエラー。
    /// - Returns: 利用側へ投げるエラー。
    static func translated(_ error: any Error) -> any Error {
        guard let streamError = error as? AdapterLinkByteStreamError else { return error }
        switch streamError {
        case .responseTimedOut:
            return VehicleIdentificationError.responseTimedOut
        case .receiveBufferOverflow:
            return VehicleIdentificationError.malformedResponse
        case .notReady, .leaseUnavailable, .leaseNotHeld, .readInProgress, .linkLost, .writeFailed:
            return VehicleIdentificationError.connectionFailed
        }
    }
}
