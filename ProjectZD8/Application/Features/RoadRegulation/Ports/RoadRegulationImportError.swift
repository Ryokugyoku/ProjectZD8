import Foundation

/// 交通規制データの取得・取り込みの失敗です。中止は `CancellationError` のまま伝えます。
nonisolated enum RoadRegulationImportError: Error, Equatable, Sendable {
    /// 一覧の通信に失敗した。
    case catalogUnavailable
    /// 一覧の形式が変わった(読めない・typeD が無い・有効な行が0・リンクの形式違い)。
    case catalogFormatChanged
    /// 選んだ都道府県が一覧に無い。
    case prefectureNotInCatalog
    /// ZIP のダウンロードに失敗した。
    case downloadFailed
    /// ZIP の構造・CRC・圧縮方式が不正。
    case archiveInvalid
    /// CSV の形式が変わった(列・版・長すぎる行・引用符)。
    case csvFormatChanged
    /// 取り込める規制が0件だった。
    case noRegulationsInArchive
    /// 空き容量が足りない。
    case insufficientStorage
    /// 保存先が使えない。
    case storageUnavailable
}
