/// PID変換定義を永続化してService/PID単位で取得する能力です。
protocol OBDPIDDefinitionRepository {
    /// 定義の改訂番号が新しい場合だけ登録または更新します。
    ///
    /// 責務: 1件のPID定義をService/PID複合識別子へ非破壊で保存します。
    /// - Parameter definition: 保存する検証済みPID定義。
    /// - Throws: スキーマ制約または永続化に失敗した場合のリポジトリエラー。
    func upsert(_ definition: OBDPIDDefinition) throws

    /// 指定Service/PIDの現在定義を取得します。
    ///
    /// 責務: 1件のService/PID複合識別子に対応する現在定義を返します。
    /// - Parameters:
    ///   - service: OBD Service番号。
    ///   - pid: Service内PID番号。
    /// - Returns: 登録済み定義。未登録の場合は `nil`。
    /// - Throws: 永続読込に失敗した場合のリポジトリエラー。
    func definition(service: UInt8, pid: UInt8) throws -> OBDPIDDefinition?
}
