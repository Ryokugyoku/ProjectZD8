import Foundation

nonisolated extension Date {
    /// UTCのUnixエポックからのミリ秒です。データベースの `…At` 列へ保存する表現です。
    var epochMilliseconds: Int64 {
        Int64((timeIntervalSince1970 * 1000).rounded())
    }

    /// 責務: データベースのミリ秒値から日時を復元します。
    init(epochMilliseconds: Int64) {
        self.init(timeIntervalSince1970: Double(epochMilliseconds) / 1000)
    }
}
