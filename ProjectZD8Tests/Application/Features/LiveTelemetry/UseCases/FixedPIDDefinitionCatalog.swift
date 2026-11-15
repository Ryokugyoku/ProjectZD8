@testable import ProjectZD8

/// 固定のPID定義一覧を返す、または読込を失敗させるPIDカタログのフェイクです。
struct FixedPIDDefinitionCatalog: OBDPIDDefinitionRepository {
    /// 読込時に返す定義です。
    private let definitionsValue: [OBDPIDDefinition]
    /// 読込時に投げるエラーです。`nil` の場合は投げません。
    private let failure: (any Error)?

    /// 返す定義または読込失敗を指定して生成します。
    ///
    /// 責務: 1件のテストで使うカタログ内容を固定します。
    /// - Parameters:
    ///   - definitions: 読込時に返す定義。
    ///   - failure: 読込時に投げるエラー。
    init(definitions: [OBDPIDDefinition], failure: (any Error)? = nil) {
        definitionsValue = definitions
        self.failure = failure
    }

    /// 固定定義を返します。
    ///
    /// 責務: 指定した失敗があれば投げ、なければ固定定義を返します。
    /// - Returns: 初期化時の定義。
    /// - Throws: `failure` を指定した場合はそのエラー。
    func definitions() throws -> [OBDPIDDefinition] {
        if let failure { throw failure }
        return definitionsValue
    }

    /// テスト対象外の書込を変更なしで受け付けます。
    ///
    /// 責務: 定義保存要求を副作用なしで完了します。
    /// - Parameter definition: 使用しない定義。
    func upsert(_ definition: OBDPIDDefinition) throws {}

    /// 固定定義からService/PIDの一致を返します。
    ///
    /// 責務: 1件のService/PIDを固定定義の検索へ変換します。
    /// - Parameters:
    ///   - service: OBD Service番号。
    ///   - pid: Service内PID番号。
    /// - Returns: 一致する定義。
    func definition(service: UInt8, pid: UInt8) throws -> OBDPIDDefinition? {
        definitionsValue.first { $0.service == service && $0.pid == pid }
    }
}
