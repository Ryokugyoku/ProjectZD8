#if os(macOS)
import Darwin
import Foundation
import OSLog

/// OBDLink EXのFTDI仮想COMポートを115200 bpsで扱います。
actor MacOSOBDLinkEXSerialTransport: OBDCommandTransport {
    /// 個人識別値や応答本文を含めず通信境界の失敗段階だけを記録します。
    private static let logger = Logger(subsystem: "Ryokugyoku.ProjectZD8", category: "OBDSerialTransport")
    /// EXが公開するBSDシリアルデバイスパスです。
    private let devicePath: String
    /// 現在開いているファイル記述子です。
    private var fileDescriptor: Int32 = -1
    /// 1応答を待つ最大時間です。
    private let responseTimeout: Duration

    /// シリアルデバイスパスと応答期限を保持して生成します。
    ///
    /// 責務: 1件のEX仮想COM終端に必要な読取設定を固定します。
    /// - Parameters:
    ///   - devicePath: IORegistryから取得したBSDシリアルデバイスパス。
    ///   - responseTimeout: `>` プロンプトを待つ最大時間。
    init(devicePath: String, responseTimeout: Duration = .seconds(12)) {
        self.devicePath = devicePath
        self.responseTimeout = responseTimeout
    }

    /// EXのシリアル終端を115200 bps、8N1、Raw modeで開きます。
    ///
    /// 責務: 1件の検証済みBSDシリアルパスをEX既定速度の非同期読書き状態へ遷移させます。
    /// - Throws: パス不正、open、termios設定に失敗した場合は `VehicleIdentificationError.connectionFailed`。
    func open() async throws {
        guard fileDescriptor < 0,
              devicePath.hasPrefix("/dev/cu.") || devicePath.hasPrefix("/dev/tty.") else {
            Self.logger.error("Serial open rejected before system call")
            throw VehicleIdentificationError.connectionFailed
        }
        let descriptor = Darwin.open(devicePath, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard descriptor >= 0 else {
            Self.logger.error("Serial open failed with errno \(errno, privacy: .public)")
            throw VehicleIdentificationError.connectionFailed
        }
        var options = termios()
        guard tcgetattr(descriptor, &options) == 0 else {
            Self.logger.error("Serial tcgetattr failed with errno \(errno, privacy: .public)")
            Darwin.close(descriptor)
            throw VehicleIdentificationError.connectionFailed
        }
        cfmakeraw(&options)
        guard cfsetspeed(&options, speed_t(B115200)) == 0 else {
            Self.logger.error("Serial cfsetspeed failed with errno \(errno, privacy: .public)")
            Darwin.close(descriptor)
            throw VehicleIdentificationError.connectionFailed
        }
        options.c_cflag |= tcflag_t(CLOCAL | CREAD)
        guard tcsetattr(descriptor, TCSANOW, &options) == 0 else {
            Self.logger.error("Serial tcsetattr failed with errno \(errno, privacy: .public)")
            Darwin.close(descriptor)
            throw VehicleIdentificationError.connectionFailed
        }
        tcflush(descriptor, TCIOFLUSH)
        fileDescriptor = descriptor
        Self.logger.info("Serial boundary opened")
    }

    /// 完全なASCIIコマンドをシリアル終端へ書き込みます。
    ///
    /// 責務: 1件のコマンドに属する全バイトを順序を保ってEXへ送ります。
    /// - Parameter data: 復帰文字終端のASCIIコマンド。
    /// - Throws: 切断、取消し、書込み失敗の場合の識別エラー。
    func write(_ data: Data) async throws {
        guard fileDescriptor >= 0 else { throw VehicleIdentificationError.connectionFailed }
        var offset = 0
        while offset < data.count {
            try Task.checkCancellation()
            let written = data.withUnsafeBytes { buffer -> Int in
                guard let base = buffer.baseAddress else { return 0 }
                return Darwin.write(fileDescriptor, base.advanced(by: offset), data.count - offset)
            }
            if written > 0 {
                offset += written
            } else if written < 0, errno != EAGAIN && errno != EWOULDBLOCK {
                Self.logger.error("Serial write failed with errno \(errno, privacy: .public)")
                throw VehicleIdentificationError.connectionFailed
            } else {
                try await Task.sleep(for: .milliseconds(10))
            }
        }
    }

    /// 次のELM/STNプロンプトまでシリアルバイトを読み取ります。
    ///
    /// 責務: 現在コマンドの応答を最初の `>` 境界まで欠落なく収集します。
    /// - Returns: `>` を含む加工前応答。
    /// - Throws: 期限切れ、取消し、読取失敗の場合の識別エラー。
    func readUntilPrompt() async throws -> Data {
        guard fileDescriptor >= 0 else { throw VehicleIdentificationError.connectionFailed }
        let deadline = ContinuousClock.now.advanced(by: responseTimeout)
        var response = Data()
        var buffer = [UInt8](repeating: 0, count: 512)
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            let count = Darwin.read(fileDescriptor, &buffer, buffer.count)
            if count > 0 {
                response.append(contentsOf: buffer.prefix(count))
                if response.contains(0x3E) { return response }
            } else if count == 0 || (count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
                try await Task.sleep(for: .milliseconds(10))
            } else {
                Self.logger.error("Serial read failed with errno \(errno, privacy: .public)")
                throw VehicleIdentificationError.connectionFailed
            }
        }
        Self.logger.error("Serial response timed out")
        throw VehicleIdentificationError.responseTimedOut
    }

    /// 開いているシリアル終端を閉じます。
    ///
    /// 責務: 現在のEXファイル記述子を1回だけ閉じて無効化します。
    func close() async {
        guard fileDescriptor >= 0 else { return }
        Darwin.close(fileDescriptor)
        fileDescriptor = -1
        Self.logger.info("Serial boundary closed")
    }
}
#endif
