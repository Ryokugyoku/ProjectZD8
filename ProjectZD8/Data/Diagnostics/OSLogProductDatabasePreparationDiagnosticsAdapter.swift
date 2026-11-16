import Foundation
import OSLog

/// 製品DBの準備失敗を統合ログ(`Logger`)へ出力します。
@MainActor
final class OSLogProductDatabasePreparationDiagnosticsAdapter: ProductDatabasePreparationDiagnosticsPort {
    /// 出力先のロガーです。
    private let logger = Logger(subsystem: DiagnosticsLogSubsystem.identifier, category: "ProductDatabasePersistence")

    /// 診断記録を出力する状態で生成します。
    ///
    /// 責務: 状態を持たない出力先を用意します。
    init() {}

    /// 保存先の準備に失敗したことを出力します。
    ///
    /// 責務: 保存先の種類とエラーのドメイン・コードを公開で、エラーの説明(パスなどを含み得る)を非公開で error として出力します。
    /// - Parameters:
    ///   - storage: 利用不能へ差し替えた保存先。
    ///   - error: 準備に失敗した元のエラー。
    func preparationFailed(_ storage: ProductDatabaseStorageKind, error: any Error) {
        let nsError = error as NSError
        logger.error(
            """
            Product database preparation failed: storage=\(storage.rawValue, privacy: .public) \
            domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public) \
            error=\(String(describing: error), privacy: .private)
            """
        )
    }
}
