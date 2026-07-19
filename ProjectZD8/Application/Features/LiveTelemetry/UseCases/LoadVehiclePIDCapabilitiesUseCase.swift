import Foundation

/// 車両別の保存済み対応PIDを再利用し、未収集時だけService 01ビットマップを探索します。
struct LoadVehiclePIDCapabilitiesUseCase: Sendable {
    /// 車両別対応PIDの永続化境界です。
    private let repository: any VehiclePIDCapabilityRepository
    /// Service 01対応ビットマップを読み取る通信境界です。
    private let telemetry: any OBDPIDTelemetryPort
    /// 対応確認日時を供給するクロックです。
    private let now: @Sendable () -> Date

    /// 永続化、通信、時刻境界を固定します。
    ///
    /// 責務: 車両別対応PIDの再利用または初回探索に必要な境界を保持します。
    /// - Parameters:
    ///   - repository: 車両別対応PID保存先。
    ///   - telemetry: 対応ビットマップ読取境界。
    ///   - now: 対応確認日時の供給元。
    init(
        repository: any VehiclePIDCapabilityRepository,
        telemetry: any OBDPIDTelemetryPort,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.repository = repository
        self.telemetry = telemetry
        self.now = now
    }

    /// 保存済み設定を返し、0件の場合だけ00から連鎖する0x20刻みの範囲を探索します。
    ///
    /// 責務: 1台の車両を収集選択付き対応PID一覧へ変換します。
    /// - Parameters:
    ///   - vehicleID: 対応PIDを取得するアプリ内車両ID。
    ///   - endpoint: 未収集時に探索へ使用するOBD終端。
    /// - Returns: 保存済みまたは新規登録した対応PID設定。
    /// - Throws: 永続化、通信、またはビットマップ応答が不正な場合のエラー。
    func execute(vehicleID: VehicleID, endpoint: OBDConnectionEndpoint) async throws -> [VehiclePIDCapability] {
        let stored = try repository.capabilities(for: vehicleID)
        guard stored.isEmpty else { return stored }
        let requests = try await discover(using: endpoint)
        let discoveredAt = now()
        let capabilities = requests.map {
            VehiclePIDCapability(vehicleID: vehicleID, request: $0, isCollectionEnabled: true, discoveredAt: discoveredAt)
        }
        try repository.insertInitial(capabilities, for: vehicleID)
        return capabilities
    }

    /// Service 01の対応範囲ビットマップを継続ビットに従って読み取ります。
    ///
    /// 責務: 00からE0までの0x20刻み照会連鎖を対応データPID集合へ変換します。
    /// - Parameter endpoint: 探索へ使用するOBD終端。
    /// - Returns: 対応が通知されたデータPIDの昇順一覧。
    /// - Throws: 通信失敗または4バイト未満の応答の場合のエラー。
    private func discover(using endpoint: OBDConnectionEndpoint) async throws -> [OBDPIDRequest] {
        var supported: [OBDPIDRequest] = []
        var base: UInt8 = 0x00
        while base <= 0xE0 {
            let query = OBDPIDRequest(service: 0x01, pid: base)
            let response = try await telemetry.read([query], using: endpoint)
            guard let bytes = response[query], bytes.count >= 4 else {
                throw OBDPIDTelemetryError.noVehicleResponse
            }
            for offset in 1...32 where bitIsSet(offset: offset, bytes: bytes) {
                let value = Int(base) + offset
                guard value <= 0xFF, value % 0x20 != 0 else { continue }
                supported.append(OBDPIDRequest(service: 0x01, pid: UInt8(value)))
            }
            guard bitIsSet(offset: 32, bytes: bytes), base < 0xE0 else { break }
            base &+= 0x20
        }
        return supported
    }

    /// 4バイト対応ビットマップ内のPID位置を判定します。
    ///
    /// 責務: 1始まりのPIDオフセットをbig-endianビットマップの真偽へ変換します。
    /// - Parameters:
    ///   - offset: 1から32のPIDオフセット。
    ///   - bytes: 対応ビットマップ先頭4バイト。
    /// - Returns: 対応ビットが立っている場合は `true`。
    private func bitIsSet(offset: Int, bytes: [UInt8]) -> Bool {
        let zeroBased = offset - 1
        return bytes[zeroBased / 8] & (0x80 >> UInt8(zeroBased % 8)) != 0
    }
}
