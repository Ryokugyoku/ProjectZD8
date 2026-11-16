import Foundation

/// PID定義DBから取得ループの読取対象を選び、PID通信セッションの終了を取得境界へ伝えます。
///
/// 型名は旧来の一括読取の名残です。実車からの読取と数値化・Raw保存は取得ループ(`LiveTelemetryAcquisitionLoop`)と
/// 取得記録(`ConnectionSessionAcquisitionRecorder`)が担い、この型は読取対象の定義を選ぶことと終了の通知だけを行います。
struct ReadMajorOBDPIDsUseCase {
    /// 読取対象を取得するPID定義永続化境界です。
    private let definitionRepository: any OBDPIDDefinitionRepository
    /// PID通信セッションの終了を伝える取得境界です。
    private let telemetry: any OBDPIDTelemetryPort

    /// PID定義Repositoryと取得境界を固定します。
    ///
    /// 責務: 読取対象の定義の取得元と、PID通信セッションの終了先を保持します。
    /// - Parameters:
    ///   - definitionRepository: 読取時点のPID定義一覧を返す永続化境界。
    ///   - telemetry: PID通信セッションを持つ取得境界。
    init(definitionRepository: any OBDPIDDefinitionRepository, telemetry: any OBDPIDTelemetryPort) {
        self.definitionRepository = definitionRepository
        self.telemetry = telemetry
    }

    /// DB登録済みの全PID定義を読み込みます。
    ///
    /// 責務: 現在のPID定義永続化状態を空でない読取対象一覧へ変換します。
    /// - Returns: Service/PID順のPID定義一覧。
    /// - Throws: PID定義読込に失敗した場合または一覧が空の場合は `OBDPIDTelemetryError.definitionCatalogUnavailable`。
    func loadDefinitions() throws -> [OBDPIDDefinition] {
        let definitions: [OBDPIDDefinition]
        do {
            definitions = try definitionRepository.definitions()
        } catch {
            throw OBDPIDTelemetryError.definitionCatalogUnavailable
        }
        let decodable = definitions.filter(\.isDecodable)
        guard !decodable.isEmpty else {
            throw OBDPIDTelemetryError.definitionCatalogUnavailable
        }
        return decodable
    }

    /// 車両設定で収集有効な対応PIDに一致する数値化可能定義を読み込みます。
    ///
    /// 責務: 車両別収集選択を安全に数値化できるPID定義一覧へ変換します。
    /// - Parameter capabilities: 車両で確認済みの対応PID設定。
    /// - Returns: 収集有効かつ数式確認済みの定義一覧。
    /// - Throws: PIDカタログ読込に失敗した場合または対象が空の場合のエラー。
    func loadDefinitions(for capabilities: [VehiclePIDCapability]) throws -> [OBDPIDDefinition] {
        let enabled = Set(capabilities.filter(\.isCollectionEnabled).map(\.id.request))
        let definitions = try loadDefinitions().filter {
            enabled.contains(OBDPIDRequest(service: $0.service, pid: $0.pid))
        }
        guard !definitions.isEmpty else { throw OBDPIDTelemetryError.definitionCatalogUnavailable }
        return definitions
    }

    /// 未登録車両で、ECUが対応を返した標準PIDに一致する数値化可能定義を読み込みます。
    ///
    /// 責務: 車種専用定義を除き、対応PIDビットマップで対応が示されたService/PIDの定義だけを返します。
    /// - Parameter supported: ECUが対応を返した標準PID。
    /// - Returns: 対応が示されたService/PIDの標準定義。
    /// - Throws: PIDカタログ読込に失敗した場合または対象が空の場合は `OBDPIDTelemetryError.definitionCatalogUnavailable`。
    func loadStandardDefinitions(supported: [OBDPIDRequest]) throws -> [OBDPIDDefinition] {
        let supportedSet = Set(supported)
        let definitions = try loadDefinitions().filter {
            !$0.isVehicleSpecific && supportedSet.contains(OBDPIDRequest(service: $0.service, pid: $0.pid))
        }
        guard !definitions.isEmpty else { throw OBDPIDTelemetryError.definitionCatalogUnavailable }
        return definitions
    }

    /// 現在のPID通信セッションを終了します。
    ///
    /// 責務: 注入済みPID取得境界へ接続資源の終了を通知します。
    func endSession() async {
        await telemetry.endSession()
    }
}
