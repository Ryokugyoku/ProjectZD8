import Foundation

/// 公式VIN構成で現行世代SUBARU BRZと確認できる識別子だけを判定します。
struct CurrentGenerationBRZVINPolicy {
    /// 判定根拠とする北米向けSUBARU VIN構成資料です。
    static let sourceURI = "https://vpic.nhtsa.dot.gov/mid/home/displayfile/72bb4585-2803-4a75-a8dd-47b21498cc21"

    /// OBDから観測したVINが現行世代BRZの確認済み接頭辞を持つか判定します。
    ///
    /// 責務: 1件の17文字VINを公式資料の `JF1ZD` 車種識別へ照合します。
    /// - Parameter vin: OBD Service 09 PID 02から観測したVIN。
    /// - Returns: 17文字かつ `JF1ZD` で始まる場合は `true`。
    func matches(_ vin: String?) -> Bool {
        guard let normalizedVIN = vin?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased(),
              normalizedVIN.count == 17 else { return false }
        return normalizedVIN.hasPrefix("JF1ZD")
    }
}
