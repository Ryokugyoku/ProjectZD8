#if os(iOS) || os(macOS)
import Foundation

/// 書き込みバイト列を最大書き込み長ごとに順序を保って分割します。
nonisolated struct BLEWriteChunker: Sendable {
    /// 分割できない理由です。
    enum Failure: Error, Equatable, Sendable {
        /// 最大書き込み長が0以下でした。CoreBluetoothが異常な値を返した状態として明示的に失敗させます。
        case invalidMaximumLength(Int)
    }

    /// バイト列を最大書き込み長以内のチャンクへ分割します。
    ///
    /// 責務: 1件のバイト列を元の順序のまま最大長以内の連続チャンクへ分けます。
    /// - Parameters:
    ///   - data: 分割するバイト列。空なら空配列を返します。
    ///   - maximumLength: 1チャンクの最大バイト数。
    /// - Returns: 連結すると元のバイト列に戻るチャンク列。
    /// - Throws: `maximumLength` が0以下の場合は `Failure.invalidMaximumLength`。
    func chunks(of data: Data, maximumLength: Int) throws -> [Data] {
        guard maximumLength > 0 else { throw Failure.invalidMaximumLength(maximumLength) }
        guard !data.isEmpty else { return [] }
        return stride(from: data.startIndex, to: data.endIndex, by: maximumLength).map { start in
            data.subdata(in: start..<min(start + maximumLength, data.endIndex))
        }
    }
}
#endif
