import Foundation

/// 共有製品DB接続から製品DBを使う保存先を組み立て、準備に失敗したら元のエラーを診断へ残して利用不能な保存先へ差し替えます。
///
/// iOS と macOS の組み立てが同じ処理を複製しないよう、両方からこの型を呼びます。差し替えのふるまいは従来どおりです。
struct ProductDatabaseRepositoryFactory {
    /// 準備の失敗を残す診断記録です。
    private let diagnostics: any ProductDatabasePreparationDiagnosticsPort

    /// 診断記録の出力先を固定して生成します。
    ///
    /// 責務: 準備の失敗の記録先を保持します。テストは記録を確かめる偽物を渡します。
    /// - Parameter diagnostics: 準備の失敗を残す診断記録。`nil` なら統合ログ(`OSLogProductDatabasePreparationDiagnosticsAdapter`)。
    init(diagnostics: (any ProductDatabasePreparationDiagnosticsPort)? = nil) {
        self.diagnostics = diagnostics ?? OSLogProductDatabasePreparationDiagnosticsAdapter()
    }

    /// 保存先を組み立て、失敗したら診断へ残して利用不能な保存先を返します。
    ///
    /// 責務: 1件の保存先の準備を成功時はそのまま、失敗時は診断1件と利用不能な保存先へ変換します。
    /// - Parameters:
    ///   - storage: 組み立てる保存先の種類。
    ///   - build: 保存先を組み立てる処理。
    ///   - unavailable: 準備失敗時に返す利用不能な保存先を作る処理。
    /// - Returns: 組み立てた保存先、または利用不能な保存先。
    func prepare<Repository>(
        _ storage: ProductDatabaseStorageKind,
        build: () throws -> Repository,
        unavailable: () -> Repository
    ) -> Repository {
        do {
            return try build()
        } catch {
            diagnostics.preparationFailed(storage, error: error)
            return unavailable()
        }
    }

    /// PID定義の保存先を生成し、確認済みseedを非破壊登録します。
    ///
    /// 責務: PID定義の永続化を利用可能なGRDB実装または明示的な利用不能境界へ変換します。
    /// - Parameter database: プロセス内で共有する製品DB接続。
    /// - Returns: seed登録済みPID Repository。準備失敗時は利用不能Repository。
    func makeOBDPIDDefinitionRepository(database: ApplicationDatabaseConnection) -> any OBDPIDDefinitionRepository {
        prepare(.obdPIDDefinitions) {
            let repository = try GRDBOBDPIDDefinitionRepository(databaseQueue: database.databaseQueue())
            try StandardOBDPIDSeed.install(into: repository)
            try ZD8OBDPIDSeed.install(into: repository)
            return repository
        } unavailable: {
            UnavailableOBDPIDDefinitionRepository()
        }
    }

    /// 車両別対応PIDの保存先を生成します。
    ///
    /// 責務: 車両別対応PIDの永続化を利用可能なGRDB実装または明示的な利用不能境界へ変換します。
    /// - Parameter database: プロセス内で共有する製品DB接続。
    /// - Returns: 車両別対応PID Repository。準備失敗時は利用不能Repository。
    func makeVehiclePIDCapabilityRepository(
        database: ApplicationDatabaseConnection
    ) -> any VehiclePIDCapabilityRepository & AccountVehiclePIDCapabilityErasureRepository {
        prepare(.vehiclePIDCapabilities) {
            try GRDBVehiclePIDCapabilityRepository(databaseQueue: database.databaseQueue())
        } unavailable: {
            UnavailableVehiclePIDCapabilityRepository()
        }
    }

    /// 整備記録の保存先を生成します。
    ///
    /// 責務: 整備記録の永続化を利用可能なGRDB実装または明示的な利用不能境界へ変換します。
    /// - Parameter database: プロセス内で共有する製品DB接続。
    /// - Returns: 整備記録 Repository。準備失敗時は利用不能Repository。
    func makeMaintenanceRecordRepository(database: ApplicationDatabaseConnection) -> any MaintenanceRecordRepository {
        prepare(.maintenanceRecords) {
            try GRDBMaintenanceRecordRepository(databaseQueue: database.databaseQueue())
        } unavailable: {
            UnavailableMaintenanceRecordRepository()
        }
    }

    /// 接続セッションの位置の保存先を生成します。
    ///
    /// 責務: 位置と位置記録事象の永続化を利用可能なGRDB実装または明示的な利用不能境界へ変換します。
    /// - Parameter database: プロセス内で共有する製品DB接続。
    /// - Returns: 位置 Repository。準備失敗時は利用不能Repository。
    func makeConnectionSessionLocationRepository(
        database: ApplicationDatabaseConnection
    ) -> any ConnectionSessionLocationRepository {
        prepare(.connectionSessionLocations) {
            try GRDBConnectionSessionLocationRepository(databaseQueue: database.databaseQueue())
        } unavailable: {
            UnavailableConnectionSessionLocationRepository()
        }
    }
}
