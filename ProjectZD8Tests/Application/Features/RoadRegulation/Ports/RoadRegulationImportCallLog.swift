import Foundation
@testable import ProjectZD8

/// 取り込みに関わる偽物(取得元・読み取り・空き容量・版の Repository)の呼び出しを、全体の順に記録する帳面です。
///
/// 段階の順序(空き容量 → ダウンロード → 版の開始 → 書き込み → 有効化 → 掃除)を確かめるために、偽物どうしで共有します。
nonisolated final class RoadRegulationImportCallLog: @unchecked Sendable {
    /// 記録する呼び出しです。
    nonisolated enum Step: Equatable, Sendable {
        /// `removeLeftoverDownloads()`。
        case removeLeftoverDownloads
        /// `currentCatalog()`。
        case fetchCatalog
        /// `downloadArchive(for:progress:)`。
        case download
        /// `removeDownloadedArchive(at:)`。
        case removeDownloadedArchive
        /// `availableCapacityBytes()`。
        case availableCapacity
        /// `read(archiveAt:progress:consume:)`。
        case read
        /// `activeDatasets()`。
        case activeDatasets
        /// `beginImport(_:)`。
        case beginImport
        /// `appendRegulations(_:to:)` と、その件数。
        case appendRegulations(count: Int)
        /// `activate(_:summary:activatedAt:)`。
        case activate
        /// `discard(_:)`。
        case discard
        /// `retireActiveDataset(for:)`。
        case retireActiveDataset
        /// `purgeInactiveDatasets()`。
        case purgeInactiveDatasets
    }

    /// 記録を保護するロックです。
    private let lock = NSLock()
    /// ロックで保護した、呼ばれた順の記録です。
    private var stored: [Step] = []

    /// 責務: 呼び出しを1件記録します。
    /// - Parameter step: 呼ばれたもの。
    func record(_ step: Step) {
        lock.withLock { stored.append(step) }
    }

    /// 呼ばれた順の記録です。
    var steps: [Step] {
        lock.withLock { stored }
    }

    /// 責務: 指定の呼び出しが最初に記録された位置を返します。
    /// - Parameter step: 探す呼び出し。
    /// - Returns: 位置。記録が無ければ `nil`。
    func firstIndex(of step: Step) -> Int? {
        steps.firstIndex(of: step)
    }

    /// 責務: 指定の呼び出しが最後に記録された位置を返します。
    /// - Parameter step: 探す呼び出し。
    /// - Returns: 位置。記録が無ければ `nil`。
    func lastIndex(of step: Step) -> Int? {
        steps.lastIndex(of: step)
    }

    /// 責務: 書き込み(`appendRegulations`)が最初に記録された位置を返します。
    /// - Returns: 位置。記録が無ければ `nil`。
    func firstAppendIndex() -> Int? {
        steps.firstIndex { if case .appendRegulations = $0 { true } else { false } }
    }

    /// 責務: 指定の呼び出しが記録されたかを返します。
    /// - Parameter step: 探す呼び出し。
    /// - Returns: 記録があれば `true`。
    func contains(_ step: Step) -> Bool {
        steps.contains(step)
    }
}
