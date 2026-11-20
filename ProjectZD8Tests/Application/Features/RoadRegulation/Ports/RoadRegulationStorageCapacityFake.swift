import Foundation
@testable import ProjectZD8

/// 空き容量の偽物です。ダウンロードの前と後で別の値を返します(帳面にダウンロードが記録されたかで切り替えます)。
///
/// 呼ばれた順に依存せずに「ダウンロード前の確認」と「ダウンロード後の確認」の境界値を試せるようにするためです。
nonisolated final class RoadRegulationStorageCapacityFake: RoadRegulationStorageCapacityPort, @unchecked Sendable {
    /// 呼び出しを全体の順に記録する帳面です。
    let log: RoadRegulationImportCallLog

    /// 状態を保護するロックです。
    private let lock = NSLock()
    /// ロックで保護した、ダウンロード前に返す値です。
    private var storedBeforeDownload: Int64
    /// ロックで保護した、ダウンロード後に返す値です。
    private var storedAfterDownload: Int64
    /// ロックで保護した、返した値(返した順)です。
    private var storedReturnedValues: [Int64] = []

    /// 責務: ダウンロードの前と後で返す値を指定して偽物を作ります。
    /// - Parameters:
    ///   - beforeDownload: ダウンロード前に返す空き容量。
    ///   - afterDownload: ダウンロード後に返す空き容量。
    ///   - log: 呼び出しの帳面(ダウンロードの記録で値を切り替える)。
    init(beforeDownload: Int64, afterDownload: Int64, log: RoadRegulationImportCallLog) {
        storedBeforeDownload = beforeDownload
        storedAfterDownload = afterDownload
        self.log = log
    }

    /// 責務: 返す値を差し替えます。
    func set(beforeDownload: Int64, afterDownload: Int64) {
        lock.withLock {
            storedBeforeDownload = beforeDownload
            storedAfterDownload = afterDownload
        }
    }

    /// ロックで保護した、読み取りで投げるエラーです。
    private var storedFailure: RoadRegulationRepositoryError?

    /// 責務: 空き容量の読み取りを、指定のエラーで失敗させます(`nil` で成功に戻します)。
    func fail(with error: RoadRegulationRepositoryError?) {
        lock.withLock { storedFailure = error }
    }

    /// 返した値(返した順)です。
    var returnedValues: [Int64] { lock.withLock { storedReturnedValues } }

    /// 責務: 帳面にダウンロードが記録される前か後かで、指定の値を返します。失敗の注入があれば投げます。
    func availableCapacityBytes() throws -> Int64 {
        let downloaded = log.contains(.download)
        log.record(.availableCapacity)
        return try lock.withLock {
            if let storedFailure { throw storedFailure }
            let value = downloaded ? storedAfterDownload : storedBeforeDownload
            storedReturnedValues.append(value)
            return value
        }
    }
}
