import Foundation
import GRDB

/// 交通規制データの保存・読取の失敗を `RoadRegulationRepositoryError` へ変換します。
nonisolated struct GRDBRoadRegulationErrorTranslator: Sendable {
    /// 任意の失敗を `RoadRegulationRepositoryError` へ変換します。
    ///
    /// 責務: 分類済みの失敗はそのまま、時刻の変換失敗・符号化の失敗・SQLite の制約違反は整合性エラー、
    /// SQLITE_FULL は保存領域の不足、それ以外は保存先の利用不可へ分類します。
    /// - Parameter error: Record の変換または GRDB が送出した失敗。
    /// - Returns: 呼び出し側へ返す失敗の理由。
    func repositoryError(for error: any Error) -> RoadRegulationRepositoryError {
        if let error = error as? RoadRegulationRepositoryError {
            return error
        }
        if let error = error as? DatabaseError {
            return databaseError(error)
        }
        if isIntegrityFailure(error) {
            return .integrityConflict
        }
        return .unavailable
    }

    /// SQLite の失敗を分類します。
    ///
    /// 責務: 主の結果コードで、保存領域の不足・制約違反・それ以外を分けます。
    /// - Parameter error: GRDB の失敗。
    /// - Returns: 失敗の理由。
    private func databaseError(_ error: DatabaseError) -> RoadRegulationRepositoryError {
        switch error.resultCode {
        case .SQLITE_FULL: .storageFull
        case .SQLITE_CONSTRAINT: .integrityConflict
        default: .unavailable
        }
    }

    /// 保存値の変換・復元の失敗かどうかを判定します。
    ///
    /// 責務: 時刻の変換失敗(`ConnectionSessionRepositoryError.integrityConflict`)と、行の復号・Codable の失敗を整合性の失敗とみなします。
    /// - Parameter error: 判定する失敗。
    /// - Returns: 整合性の失敗なら `true`。
    private func isIntegrityFailure(_ error: any Error) -> Bool {
        if let error = error as? ConnectionSessionRepositoryError {
            return error == .integrityConflict
        }
        return error is RowDecodingError || error is DecodingError || error is EncodingError
    }
}
