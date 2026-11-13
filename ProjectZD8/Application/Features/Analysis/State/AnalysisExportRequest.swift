import Foundation

/// Web側から届いた書き出し(CSV・PNG)の内容です。プラットフォームが保存・共有します。
nonisolated struct AnalysisExportRequest: Identifiable, Equatable, Sendable {
    let id: UUID
    /// 提案するファイル名です。
    let filename: String
    /// MIMEタイプです(`text/csv`、`image/png`)。
    let mimeType: String
    let data: Data

    /// 書き出し要求を生成します。
    ///
    /// 責務: 保存対象のバイト列とファイル名をまとめます。
    init(id: UUID = UUID(), filename: String, mimeType: String, data: Data) {
        self.id = id
        self.filename = filename
        self.mimeType = mimeType
        self.data = data
    }
}
