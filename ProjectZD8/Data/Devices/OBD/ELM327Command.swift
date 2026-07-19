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
    /// OBDLink製品名とFirmwareを含む拡張デバイス情報を要求します。
    case extendedDeviceInformation = "STDIX"
    /// 現在選択されたOBDプロトコル記述を要求します。
    case protocolDescription = "ATDP"
    /// OBD Service 09 PID 02のVINを要求します。
    case vehicleIdentificationNumber = "0902"

    /// 未加工観測で使用する安定要求識別子です。
    var requestID: String { String(describing: self) }

    /// 復帰文字を付けた送信用ASCIIデータです。
    var encodedData: Data { Data((rawValue + "\r").utf8) }
}

/// 一次資料付き定義に対応するService 01読取コマンドです。
enum ELM327CurrentDataCommand: String, CaseIterable, Sendable, ELM327CommandEncoding {
    /// エンジン冷却水温を要求します。
    case engineCoolantTemperature = "0105"
    /// エンジン回転数を要求します。
    case engineSpeed = "010C"

    /// Service/PIDの複合識別子です。
    var request: OBDPIDRequest {
        switch self {
        case .engineCoolantTemperature:
            OBDPIDRequest(service: 0x01, pid: 0x05)
        case .engineSpeed:
            OBDPIDRequest(service: 0x01, pid: 0x0C)
        }
    }

    /// 指定Service/PIDが許可済みコマンドに対応する場合だけ生成します。
    ///
    /// 責務: 1件のService/PIDを固定許可リスト内の読取コマンドへ変換します。
    /// - Parameter request: 変換するService/PID。
    init?(request: OBDPIDRequest) {
        guard let command = Self.allCases.first(where: { $0.request == request }) else { return nil }
        self = command
    }

    /// 未加工観測で使用する安定要求識別子です。
    var requestID: String { String(describing: self) }

    /// 復帰文字を付けた送信用ASCIIデータです。
    var encodedData: Data { Data((rawValue + "\r").utf8) }
}
