import Foundation

/// アダプターの通信経路とOSに応じたTransportを選び、初期化済みのOBDリンクを返します。`.demo` には模擬リンクを返します。
nonisolated struct SystemOBDLinkPort: OBDLinkPort {
    /// アダプターから未開通のTransportを作る処理です。対応しない組み合わせは `OBDTransportError.transportUnsupported` を投げます。
    typealias TransportFactory = @MainActor @Sendable (AdapterDescriptor) throws -> any OBDCommandTransport

    /// Transportを作る処理です。
    private let makeTransport: TransportFactory
    /// 識別情報の観測日時を供給します。
    private let now: @Sendable () -> Date
    /// デモリンクを作る処理です。
    private let makeDemoLink: @Sendable () -> any OBDLink

    /// 現在のOS向けの製品用ポートを生成します。
    ///
    /// 責務: OSごとに利用できるTransportの対応表を持つポートを構築します。
    init() {
        self.init(
            makeTransport: Self.systemTransportFactory(),
            now: Date.init,
            makeDemoLink: { DemoOBDLink() }
        )
    }

    /// Transport生成・時刻・デモリンクを注入して生成します。
    ///
    /// 責務: 通信経路の選択をテスト可能な境界へ固定します。
    init(
        makeTransport: @escaping TransportFactory,
        now: @escaping @Sendable () -> Date,
        makeDemoLink: @escaping @Sendable () -> any OBDLink
    ) {
        self.makeTransport = makeTransport
        self.now = now
        self.makeDemoLink = makeDemoLink
    }

    /// 責務: アダプターへ接続してELM327の初期化まで済ませたリンクを返します。
    /// - Throws: この端末で使えない経路は `transportUnsupported`、接続・初期化の失敗は対応する `OBDLinkError`。
    func open(_ adapter: AdapterDescriptor) async throws -> any OBDLink {
        if adapter.transport == .demo { return makeDemoLink() }
        let transport: any OBDCommandTransport
        do {
            transport = try await makeTransport(adapter)
        } catch let error as OBDTransportError where error == .transportUnsupported {
            throw OBDLinkError.transportUnsupported
        } catch {
            throw OBDLinkError.connectionFailed
        }
        return try await ELM327OBDLink.connect(transport: transport, now: now)
    }

    #if os(iOS)
    /// 責務: iOSで利用できるTransport(BLE UART、ExternalAccessory)の対応表を返します。
    private static func systemTransportFactory() -> TransportFactory {
        let configuration = IOSExternalAccessoryProtocolConfiguration()
        return { adapter in
            switch adapter.transport {
            case .bluetoothLowEnergy:
                return try AppleCoreBluetoothOBDTransport(adapter: adapter)
            case .bluetoothClassic:
                return try IOSExternalAccessoryOBDTransport(adapter: adapter, configuration: configuration)
            case .usbSerial, .demo:
                throw OBDTransportError.transportUnsupported
            }
        }
    }
    #elseif os(macOS)
    /// 責務: macOSで利用できるTransport(BLE UART、RFCOMM、USBシリアル)の対応表を返します。
    private static func systemTransportFactory() -> TransportFactory {
        { adapter in
            switch adapter.transport {
            case .bluetoothLowEnergy:
                return try AppleCoreBluetoothOBDTransport(adapter: adapter)
            case .bluetoothClassic:
                return MacOSBluetoothRFCOMMOBDTransport(deviceAddress: adapter.systemIdentifier)
            case .usbSerial:
                return MacOS115200BaudOBDSerialTransport(devicePath: adapter.systemIdentifier)
            case .demo:
                throw OBDTransportError.transportUnsupported
            }
        }
    }
    #endif
}
