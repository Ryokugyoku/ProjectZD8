import Foundation
@testable import ProjectZD8

/// 製品DBの準備失敗の診断記録を、受け取った順に保持する偽物です。
@MainActor
final class ProductDatabasePreparationDiagnosticsSpy: ProductDatabasePreparationDiagnosticsPort {
    /// 1件の診断記録です。
    struct Entry {
        /// 利用不能へ差し替えた保存先です。
        let storage: ProductDatabaseStorageKind
        /// 渡された元のエラーです。
        let error: any Error
    }

    /// 受け取った診断記録です。受け取った順に並びます。
    private(set) var entries: [Entry] = []

    /// 記録の無い状態で生成します。
    ///
    /// 責務: 空の記録先を用意します。
    init() {}

    /// 受け取った診断を記録します。
    ///
    /// 責務: 保存先の種類と元のエラーをそのまま保持します。
    /// - Parameters:
    ///   - storage: 利用不能へ差し替えた保存先。
    ///   - error: 準備に失敗した元のエラー。
    func preparationFailed(_ storage: ProductDatabaseStorageKind, error: any Error) {
        entries.append(Entry(storage: storage, error: error))
    }
}
