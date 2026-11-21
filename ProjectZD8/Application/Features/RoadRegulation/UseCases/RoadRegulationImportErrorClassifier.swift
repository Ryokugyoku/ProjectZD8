import Foundation

/// 取り込み・一覧・削除の途中で起きた失敗を、画面へ伝える `RoadRegulationImportError` に分類する型です。
///
/// - `CancellationError` は取り消しとして区別します(エラーとして表示しません)。
/// - `RoadRegulationImportError` はそのまま使います。
/// - リポジトリの `storageFull` は `insufficientStorage`、ほかのリポジトリの失敗は `storageUnavailable` にします。
/// - それ以外の想定外の失敗は、呼び出し元が段階ごとに決めた代わりの値にします(成功や空に潰しません)。
nonisolated struct RoadRegulationImportErrorClassifier: Sendable {
    /// 状態を持たない分類器を作ります。
    ///
    /// 責務: 分類器を構築します。
    init() {}

    /// 失敗を取り込みのエラーに分類します。
    ///
    /// 責務: 取り消しを `nil` として区別し、それ以外を取り込みのエラーへ変換します。
    /// - Parameters:
    ///   - error: 分類する失敗。
    ///   - fallback: 想定外の失敗に使う値。
    /// - Returns: 取り込みのエラー。取り消しなら `nil`。
    func importError(for error: any Error, fallback: RoadRegulationImportError) -> RoadRegulationImportError? {
        switch error {
        case is CancellationError:
            return nil
        case let importError as RoadRegulationImportError:
            return importError
        case let repositoryError as RoadRegulationRepositoryError:
            return repositoryError == .storageFull ? .insufficientStorage : .storageUnavailable
        default:
            return fallback
        }
    }

    /// 失敗を、呼び出し元へ投げ直す値に分類します。
    ///
    /// 責務: 取り消しは `CancellationError` のまま、それ以外は取り込みのエラーにして返します。
    /// - Parameters:
    ///   - error: 分類する失敗。
    ///   - fallback: 想定外の失敗に使う値。
    /// - Returns: 投げ直すエラー。
    func classified(_ error: any Error, fallback: RoadRegulationImportError) -> any Error {
        importError(for: error, fallback: fallback) ?? CancellationError()
    }
}
