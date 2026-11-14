/// 受信監視で受け取るCAN IDを絞るフィルターコマンド列を、チップ系統に応じて生成します。
nonisolated struct ELM327MonitorFilterCommandBuilder: Sendable {
    /// CAN ID集合とチップ系統からフィルターコマンド列を生成します。
    ///
    /// 責務: ID集合の幅を検証した後、ELM327系は`ATCRA`または`ATCF`+`ATCM`、STN系はID昇順の`STFAP`列へ変換します。
    /// - Parameters:
    ///   - identifiers: 受信するCAN ID。
    ///   - chipFamily: 接続中アダプターのチップ系統。
    /// - Returns: 送信順のコマンド列、または生成できなかった理由。
    func commands(
        for identifiers: Set<UInt32>,
        chipFamily: OBDAdapterChipFamily
    ) -> Result<[any ELM327CommandEncoding], ELM327MonitorFilterCommandBuildError> {
        let width: ELM327CANIdentifierWidth
        switch Self.commonWidth(of: identifiers) {
        case .success(let common): width = common
        case .failure(let error): return .failure(error)
        }
        switch chipFamily {
        case .elm327Genuine, .elm327Clone: return Self.elm327Commands(for: identifiers, width: width)
        case .stn: return Self.stnCommands(for: identifiers, width: width)
        case .unknown: return .failure(.unsupportedChipFamily)
        }
    }

    /// ID集合が共通して属する幅を決めます。
    ///
    /// 責務: 空集合、29bit超え、11bit/29bitの混在をそれぞれ失敗にします。
    /// - Parameter identifiers: 検証するCAN ID。
    /// - Returns: 全IDに共通の幅。
    private static func commonWidth(
        of identifiers: Set<UInt32>
    ) -> Result<ELM327CANIdentifierWidth, ELM327MonitorFilterCommandBuildError> {
        guard !identifiers.isEmpty else { return .failure(.emptyIdentifiers) }
        let widths = identifiers.map(ELM327CANIdentifierWidth.init(identifier:))
        guard !widths.contains(nil) else { return .failure(.identifierOutOfRange) }
        let distinct = Set(widths.compactMap { $0 })
        guard distinct.count == 1, let width = distinct.first else { return .failure(.mixedIdentifierWidths) }
        return .success(width)
    }

    /// ELM327系のフィルターコマンド列を生成します。
    ///
    /// 責務: 1件なら`ATCRA`、複数件なら全IDで一致するビットのマスクと、それを適用したフィルター値の`ATCF`/`ATCM`にします。
    /// - Parameters:
    ///   - identifiers: 幅検証済みの空でないCAN ID。
    ///   - width: 全IDに共通の幅。
    /// - Returns: 送信順のコマンド列。幅検証済みのため通常は失敗しませんが、生成できない値は空列にせず失敗にします。
    private static func elm327Commands(
        for identifiers: Set<UInt32>,
        width: ELM327CANIdentifierWidth
    ) -> Result<[any ELM327CommandEncoding], ELM327MonitorFilterCommandBuildError> {
        let sorted = identifiers.sorted()
        let isExtended = width == .extended
        if sorted.count == 1 {
            guard let receive = ELM327CANReceiveAddressCommand(identifier: sorted[0]) else { return .failure(.identifierOutOfRange) }
            return .success([receive])
        }
        let differingBits = sorted.reduce(UInt32(0)) { $0 | ($1 ^ sorted[0]) }
        let mask = ~differingBits & width.maximumValue
        guard let filter = ELM327CANFilterCommand(identifier: sorted[0] & mask, isExtended: isExtended),
              let maskCommand = ELM327CANMaskCommand(mask: mask, isExtended: isExtended) else {
            return .failure(.identifierOutOfRange)
        }
        return .success([filter, maskCommand])
    }

    /// STN系のフィルターコマンド列を生成します。
    ///
    /// 責務: ID昇順に、全ビットを比較する通過フィルターを1件ずつ生成します。
    /// - Parameters:
    ///   - identifiers: 幅検証済みの空でないCAN ID。
    ///   - width: 全IDに共通の幅。
    /// - Returns: 送信順のコマンド列。幅検証済みのため通常は失敗しませんが、生成できない値は省かず失敗にします。
    private static func stnCommands(
        for identifiers: Set<UInt32>,
        width: ELM327CANIdentifierWidth
    ) -> Result<[any ELM327CommandEncoding], ELM327MonitorFilterCommandBuildError> {
        var commands: [any ELM327CommandEncoding] = []
        for identifier in identifiers.sorted() {
            guard let command = STNPassFilterCommand(pattern: identifier, mask: width.maximumValue, isExtended: width == .extended) else {
                return .failure(.identifierOutOfRange)
            }
            commands.append(command)
        }
        return .success(commands)
    }
}
