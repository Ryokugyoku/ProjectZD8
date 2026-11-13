/// PID定義DBの準備失敗を読取時まで保持します。
struct UnavailableOBDPIDDefinitionRepository: OBDPIDDefinitionRepository {
    /// PID定義DBを利用できないことを表す内部エラーです。
    private struct UnavailableError: Error {}

    /// 利用不能なPID定義リポジトリを生成します。
    ///
    /// 責務: 起動時のDB準備失敗を表すリポジトリ境界を生成します。
    init() {}

    /// PID定義DBを利用できないため失敗します。
    ///
    /// 責務: PID定義一覧の利用不能を永続読込エラーとして通知します。
    /// - Returns: この実装は値を返しません。
    /// - Throws: 常にPID定義DB利用不能エラー。
    func definitions() throws -> [OBDPIDDefinition] {
        throw UnavailableError()
    }

    /// PID定義DBを利用できないため失敗します。
    ///
    /// 責務: PID定義保存の利用不能を永続書込エラーとして通知します。
    /// - Parameter definition: 保存できないPID定義。
    /// - Throws: 常にPID定義DB利用不能エラー。
    func upsert(_ definition: OBDPIDDefinition) throws {
        throw UnavailableError()
    }

    /// PID定義DBを利用できないため失敗します。
    ///
    /// 責務: 単一PID定義読込の利用不能を永続読込エラーとして通知します。
    /// - Parameters:
    ///   - service: 読み取れないOBD Service番号。
    ///   - pid: 読み取れないService内PID番号。
    /// - Returns: この実装は値を返しません。
    /// - Throws: 常にPID定義DB利用不能エラー。
    func definition(service: UInt8, pid: UInt8) throws -> OBDPIDDefinition? {
        throw UnavailableError()
    }
}
