import Foundation

/// ELM/STNへ送信できる読取専用コマンドの符号化契約です。
protocol ELM327CommandEncoding: Sendable {
    /// 未加工観測で使用する安定要求識別子です。
    var requestID: String { get }
    /// 復帰文字を付けた送信用ASCIIデータです。
    var encodedData: Data { get }
}

/// 車両識別フローで許可する読取専用ELM/STNコマンドです。
enum ELM327Command: String, CaseIterable, Sendable, ELM327CommandEncoding {
    /// アダプターを既知の初期状態へ戻します。
    case reset = "ATZ"
    /// コマンドエコーを無効化します。
    case echoOff = "ATE0"
    /// 応答の改行追加を無効化します。
    case linefeedsOff = "ATL0"
    /// 応答バイト間の空白を有効化します。
    case spacesOn = "ATS1"
    /// 応答ヘッダー表示を無効化します。
    case headersOff = "ATH0"
    /// 法定OBDプロトコルの自動選択を有効化します。
    case automaticProtocol = "ATSP0"
    /// アダプター識別文字列を要求します。
    case adapterIdentity = "ATI"
    /// 現在選択されたOBDプロトコル記述を要求します。
    case protocolDescription = "ATDP"
    /// OBD Service 09 PID 02のVINを要求します。
    case vehicleIdentificationNumber = "0902"

    /// 未加工観測で使用する安定要求識別子です。
    var requestID: String { String(describing: self) }

    /// 復帰文字を付けた送信用ASCIIデータです。
    var encodedData: Data { Data((rawValue + "\r").utf8) }
}

/// PID定義DBで許可されたService 01読取コマンドです。
nonisolated struct ELM327CurrentDataCommand: Sendable, ELM327CommandEncoding {
    /// Service/PIDの複合識別子です。
    let request: OBDPIDRequest

    /// 指定Service/PIDが許可済みコマンドに対応する場合だけ生成します。
    ///
    /// 責務: 1件のService/PIDを固定許可リスト内の読取コマンドへ変換します。
    /// - Parameter request: 変換するService/PID。
    init?(request: OBDPIDRequest) {
        guard request.service == 0x01 else { return nil }
        self.request = request
    }

    /// 未加工観測で使用する安定要求識別子です。
    var requestID: String { String(format: "%02X%02X", request.service, request.pid) }

    /// 復帰文字を付けた送信用ASCIIデータです。
    var encodedData: Data { Data((requestID + "\r").utf8) }
}
