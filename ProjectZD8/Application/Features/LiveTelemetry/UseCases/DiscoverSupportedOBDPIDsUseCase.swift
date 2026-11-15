import Foundation

/// アダプター経由で車両ECUへ問い合わせ、対応している標準PIDと車種専用PIDを決定します。
///
/// 保存は行わず、呼び出しごとに通信して結果を返します。
struct DiscoverSupportedOBDPIDsUseCase: Sendable {
    /// Service 01対応ビットマップと車種専用PIDを読み取る通信境界です。
    private let telemetry: any OBDPIDTelemetryPort
    /// 車種専用定義を取得するPIDカタログ境界です。
    private let definitionRepository: (any OBDPIDDefinitionRepository)?

    /// 通信境界とPIDカタログ境界を固定します。
    ///
    /// 責務: 対応PID探索に必要な通信とカタログの境界を保持します。
    /// - Parameters:
    ///   - telemetry: 対応ビットマップと車種専用PIDの読取境界。
    ///   - definitionRepository: 車種専用PID定義の読込先。`nil` の場合は車種専用PIDを探索しません。
    init(
        telemetry: any OBDPIDTelemetryPort,
        definitionRepository: (any OBDPIDDefinitionRepository)? = nil
    ) {
        self.telemetry = telemetry
        self.definitionRepository = definitionRepository
    }

    /// 対応している標準PID全部と、型式がある場合はその車種専用PIDを探索します。
    ///
    /// 責務: 1回の接続を保存を伴わない対応Service/PID一覧へ変換します。
    /// - Parameters:
    ///   - vehicleModelCode: 車種専用PID探索を許可する確認済み型式。`nil` の場合は標準PIDだけを探索します。
    ///   - endpoint: 探索へ使用するOBD終端。
    /// - Returns: Service/PID昇順の対応PID一覧。
    /// - Throws: 通信失敗、ビットマップ応答不正、または定義読込失敗の場合のエラー。
    func execute(
        vehicleModelCode: String?,
        endpoint: OBDConnectionEndpoint
    ) async throws -> [OBDPIDRequest] {
        let standard = try await discoverStandard(using: endpoint)
        let vehicleSpecific = try await discoverVehicleSpecific(
            vehicleModelCode: vehicleModelCode,
            excluding: Set(standard),
            endpoint: endpoint
        )
        return (standard + vehicleSpecific).sorted { ($0.service, $0.pid) < ($1.service, $1.pid) }
    }

    /// Service 01の対応範囲ビットマップを継続ビットに従って読み取ります。
    ///
    /// 責務: 00からE0までの0x20刻み照会連鎖を対応データPID集合へ変換します。
    /// - Parameter endpoint: 探索へ使用するOBD終端。
    /// - Returns: 対応が通知されたデータPIDの昇順一覧。
    /// - Throws: 通信失敗または4バイト未満の応答の場合のエラー。
    func discoverStandard(using endpoint: OBDConnectionEndpoint) async throws -> [OBDPIDRequest] {
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

    /// 型式一致する専用PIDを個別送信し、応答済みだけを対応PIDとして返します。
    ///
    /// 責務: 1件の確認済み型式を応答確認済みの車種専用Service/PID一覧へ変換します。
    /// - Parameters:
    ///   - vehicleModelCode: 接続前識別で確認した型式。`nil` の場合は探索しません。
    ///   - excluding: 既に対応確認済みのService/PID。
    ///   - endpoint: 探索へ使用するOBD終端。
    /// - Returns: 今回正応答を確認できた車種専用Service/PID。カタログ定義順。
    /// - Throws: 定義読込または通信境界に失敗した場合のエラー。
    func discoverVehicleSpecific(
        vehicleModelCode: String?,
        excluding: Set<OBDPIDRequest>,
        endpoint: OBDConnectionEndpoint
    ) async throws -> [OBDPIDRequest] {
        guard let vehicleModelCode, let definitionRepository else { return [] }
        let definitions = try definitionRepository.definitions().filter {
            $0.vehicleModelCode?.caseInsensitiveCompare(vehicleModelCode) == .orderedSame
                && !excluding.contains(OBDPIDRequest(service: $0.service, pid: $0.pid))
        }
        guard !definitions.isEmpty else { return [] }
        let responses = try await telemetry.readVehicleSpecific(definitions, using: endpoint)
        return definitions.compactMap { definition in
            let request = OBDPIDRequest(service: definition.service, pid: definition.pid)
            return responses[request] == nil ? nil : request
        }
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
