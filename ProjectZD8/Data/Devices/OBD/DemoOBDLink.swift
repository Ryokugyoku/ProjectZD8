import Foundation

/// 実車なしで動作を確認するための模擬OBDリンクです。決定的な走行モデルの値をPIDの生バイトへ符号化して返します。
///
/// 実車データではありません。VINは `JF1ZD8` で始まり、ZD8専用PIDが有効になります。
actor DemoOBDLink: OBDLink {
    /// デモ用アダプターの記述です。探索結果には含めず、デモモードでだけ使います。
    static let adapter = AdapterDescriptor(
        transport: .demo,
        systemIdentifier: "demo",
        displayName: "RevTorque Demo",
        detail: nil
    )

    /// デモ車両のVINです(ZD8専用PIDの適用対象)。
    static let vin = "JF1ZD8AA0P0000001"

    /// デモ車両が標準サービス01で応答するPIDです。
    static let supportedStandardPIDs: Set<OBDPIDRequest> = Set(
        [0x04, 0x05, 0x06, 0x07, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10, 0x11, 0x1F, 0x2F, 0x33, 0x42, 0x46, 0x5C]
            .map { OBDPIDRequest(service: 0x01, pid: $0) }
    )

    /// 走行距離計(サービス21 PID 02)を返すECUのヘッダーです。
    private static let odometerHeader: UInt16 = 0x7E0
    /// AT油温(サービス21 PID 17)を返すECUのヘッダーです。
    private static let transmissionHeader: UInt16 = 0x7E1

    /// 走行モデルです。
    private let driveCycle: DemoDriveCycle
    /// 1問い合わせあたりの擬似遅延です。
    private let latency: Duration
    /// 識別情報の観測日時を供給します。
    private let now: @Sendable () -> Date
    /// 始動からの経過秒を供給します。
    private let elapsedSeconds: @Sendable () -> TimeInterval
    /// 閉じた後は `true` です。
    private var isClosed = false

    /// 模擬リンクを生成します。
    ///
    /// 責務: 時刻源と遅延を固定した模擬リンクを構築します。
    /// - Parameters:
    ///   - latency: 1問い合わせあたりの擬似遅延。テストでは `.zero`。
    ///   - now: 識別情報の観測日時の供給元。
    ///   - elapsedSeconds: 始動からの経過秒の供給元。既定は生成時からの実時間。
    init(
        latency: Duration = .milliseconds(30),
        now: @escaping @Sendable () -> Date = Date.init,
        elapsedSeconds: @escaping @Sendable () -> TimeInterval = DemoOBDLink.wallClockElapsedSeconds()
    ) {
        self.driveCycle = DemoDriveCycle()
        self.latency = latency
        self.now = now
        self.elapsedSeconds = elapsedSeconds
    }

    /// 責務: 呼び出した時点を始動時刻とし、以後の経過秒を返す時刻源を作ります。
    static func wallClockElapsedSeconds() -> @Sendable () -> TimeInterval {
        let start = ContinuousClock.now
        return {
            let elapsed = ContinuousClock.now - start
            return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        }
    }

    /// 責務: 模擬アダプターの識別情報を返します。
    func identify() async throws -> VehicleIdentification {
        try ensureOpen()
        return VehicleIdentification(
            vin: Self.vin,
            adapterDescription: "RevTorque Demo Adapter",
            protocolDescription: "Simulated ISO 15765-4 (CAN 11/500)",
            observedAt: now()
        )
    }

    /// 責務: 模擬車両が応答する標準PIDを返します。
    func supportedPIDs() async throws -> Set<OBDPIDRequest> {
        try ensureOpen()
        return Self.supportedStandardPIDs
    }

    /// 責務: 現在時刻の走行状態をPIDの生バイトへ符号化して返します。未対応PIDやヘッダー違いは `.noData` です。
    func query(_ request: OBDPIDRequest, header: UInt16?) async throws -> OBDQueryResult {
        try ensureOpen()
        if latency > .zero {
            try await Task.sleep(for: latency)
            try ensureOpen()
        }
        let state = driveCycle.state(at: elapsedSeconds())
        guard let payload = payload(for: request, header: header, state: state) else {
            return OBDQueryResult(outcome: .noData)
        }
        return OBDQueryResult(outcome: .responded, payload: payload)
    }

    /// 責務: リンクを閉じ、以後の要求を `connectionLost` にします。
    func close() async {
        isClosed = true
    }

    /// 責務: 閉じていれば `connectionLost` を投げます。
    private func ensureOpen() throws {
        if isClosed { throw OBDLinkError.connectionLost }
    }

    /// 責務: 1件の要求を、カタログの数式の逆変換で符号化した応答バイトへ変換します。対象外なら `nil`。
    private func payload(for request: OBDPIDRequest, header: UInt16?, state: DemoVehicleState) -> [UInt8]? {
        switch request.service {
        case 0x01:
            guard header == nil || header == 0x7DF else { return nil }
            return standardPayload(pid: request.pid, state: state)
        case 0x21:
            switch (request.pid, header) {
            case (0x02, Self.odometerHeader):
                let raw = UInt32(min(max((state.odometer * 10).rounded(), 0), Double(UInt32.max)))
                return [UInt8(raw >> 24), UInt8((raw >> 16) & 0xFF), UInt8((raw >> 8) & 0xFF), UInt8(raw & 0xFF)]
            case (0x17, Self.transmissionHeader):
                return [byte(state.transmissionFluidTemperature + 58)]
            default:
                return nil
            }
        default:
            return nil
        }
    }

    /// 責務: サービス01の1件のPIDを生バイトへ符号化します。
    private func standardPayload(pid: UInt8, state: DemoVehicleState) -> [UInt8]? {
        switch pid {
        case 0x04: [byte(state.engineLoad * 255 / 100)]
        case 0x05: [byte(state.coolantTemperature + 40)]
        case 0x06: [byte(state.shortTermFuelTrim * 128 / 100 + 128)]
        case 0x07: [byte(state.longTermFuelTrim * 128 / 100 + 128)]
        case 0x0B: [byte(state.manifoldPressure)]
        case 0x0C: word(state.engineSpeed * 4)
        case 0x0D: [byte(state.vehicleSpeed)]
        case 0x0E: [byte((state.timingAdvance + 64) * 2)]
        case 0x0F: [byte(state.intakeTemperature + 40)]
        case 0x10: word(state.massAirFlow * 100)
        case 0x11: [byte(state.throttle * 255 / 100)]
        case 0x1F: word(state.runTime)
        case 0x2F: [byte(state.fuelLevel * 255 / 100)]
        case 0x33: [101]
        case 0x42: word(state.moduleVoltage * 1000)
        case 0x46: [byte(state.ambientTemperature + 40)]
        case 0x5C: [byte(state.oilTemperature + 40)]
        default: nil
        }
    }

    /// 責務: 値を四捨五入して0〜255へ丸め、1バイトにします。
    private func byte(_ value: Double) -> UInt8 {
        UInt8(min(max(value.rounded(), 0), 255))
    }

    /// 責務: 値を四捨五入して0〜65535へ丸め、上位・下位の2バイトにします。
    private func word(_ value: Double) -> [UInt8] {
        let raw = UInt16(min(max(value.rounded(), 0), 65_535))
        return [UInt8(raw >> 8), UInt8(raw & 0xFF)]
    }
}
