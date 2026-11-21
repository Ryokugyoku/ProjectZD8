import Foundation

/// 配布の一覧 JSON(`opendata.json`)を `RoadRegulationCatalog` へ解読する純粋な型です。
nonisolated struct JARTICOpenDataIndexDecoder: Sendable {
    /// リンクを連結する配布のパスの基点。
    let downloadBaseURL: URL

    /// 一覧の解読器を作ります。
    ///
    /// 責務: リンクの連結先(配布のパス)を保持します。
    /// - Parameter downloadBaseURL: 配布のパス。https の URL を想定します。
    init(downloadBaseURL: URL = URL(string: "https://www.jartic.or.jp/d/opendata")!) {
        self.downloadBaseURL = downloadBaseURL
    }

    /// 一覧 JSON を解読します。
    ///
    /// 責務: `type` が `typeD` の最初の項目の `targetList` から、都道府県ごとの ZIP の URL と基準月を取り出します。
    /// 採用できない行(`R01`〜`R47` 以外の id、形式違いのリンク、想定外のホスト)は捨て、有効な行が0なら失敗にします。
    /// - Parameter data: JSON のバイト列。
    /// - Returns: 解読した一覧。
    /// - Throws: 形式が想定と違う時は `RoadRegulationImportError.catalogFormatChanged`。
    func decode(_ data: Data) throws -> RoadRegulationCatalog {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let typeD = root.lazy.compactMap({ $0 as? [String: Any] }).first(where: { $0["type"] as? String == "typeD" }),
              let targets = typeD["targetList"] as? [Any],
              let linkPattern = try? NSRegularExpression(pattern: #"^/([0-9]{12})/typeD_[a-z]+\.zip\z"#) else {
            throw RoadRegulationImportError.catalogFormatChanged
        }
        let entries = targets.compactMap { entry(from: $0, linkPattern: linkPattern) }
        guard !entries.isEmpty else { throw RoadRegulationImportError.catalogFormatChanged }
        return RoadRegulationCatalog(dataMonth: dataMonth(from: typeD["targetMonth"] as? String), entries: entries)
    }

    /// 1行を項目へ変えます。
    ///
    /// 責務: id とリンクの形式・ホスト・パスを検査し、採用できる行だけを返します。
    private func entry(from raw: Any, linkPattern: NSRegularExpression) -> RoadRegulationCatalogEntry? {
        guard let object = raw as? [String: Any],
              let prefecture = prefecture(from: object["id"] as? String),
              let link = object["link"] as? String,
              let stamp = publicationStamp(in: link, pattern: linkPattern),
              let url = distributionURL(for: link) else { return nil }
        return RoadRegulationCatalogEntry(prefecture: prefecture, archiveURL: url, publicationStamp: stamp)
    }

    /// リンクを配布の URL へ連結し、配布の範囲内か検査します。
    ///
    /// 責務: https・同じホストとポート・配布のパス配下・クエリとフラグメントなしの URL だけを返します。
    private func distributionURL(for link: String) -> URL? {
        guard let url = URL(string: downloadBaseURL.absoluteString + link),
              url.scheme == "https", url.host == downloadBaseURL.host, url.port == downloadBaseURL.port,
              url.path.hasPrefix(downloadBaseURL.path + "/"),
              url.query == nil, url.fragment == nil else { return nil }
        return url
    }

    /// `R01`〜`R47` の id を都道府県コードへ変えます。
    ///
    /// 責務: "R" と半角数字2桁だけを受け入れ、範囲外は `nil` にします。
    private func prefecture(from id: String?) -> JapanesePrefectureCode? {
        guard let id, id.count == 3, id.hasPrefix("R"),
              id.dropFirst().allSatisfy({ $0.isASCII && $0.isNumber }),
              let number = Int(id.dropFirst()) else { return nil }
        return JapanesePrefectureCode(number)
    }

    /// リンクの形式を検査して公開の印(12桁)を取り出します。
    ///
    /// 責務: 配布のリンクの形に一致する時だけ、先頭の12桁を返します。
    private func publicationStamp(in link: String, pattern: NSRegularExpression) -> String? {
        let range = NSRange(link.startIndex..., in: link)
        guard let match = pattern.firstMatch(in: link, range: range),
              let stampRange = Range(match.range(at: 1), in: link) else { return nil }
        return String(link[stampRange])
    }

    /// "2026年09月" 形式を基準月へ変えます。
    ///
    /// 責務: 読めない・範囲外なら `nil` にします(一覧の失敗にはしません)。
    private func dataMonth(from text: String?) -> RoadRegulationDataMonth? {
        guard let text, text.count == 8, text.dropFirst(4).hasPrefix("年"), text.hasSuffix("月") else { return nil }
        let year = text.prefix(4)
        let month = text.dropFirst(5).prefix(2)
        guard (year + month).allSatisfy({ $0.isASCII && $0.isNumber }),
              let y = Int(year), let m = Int(month) else { return nil }
        return RoadRegulationDataMonth(year: y, month: m)
    }
}
