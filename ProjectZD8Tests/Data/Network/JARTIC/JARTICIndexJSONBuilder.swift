import Foundation
@testable import ProjectZD8

/// 配布の一覧 JSON(`opendata.json`)と同じ形のバイト列を、テストコードの中で組み立てる補助です。
nonisolated enum JARTICIndexJSONBuilder {
    /// 既定の公開の印です。
    static let stamp = "202611010000"

    /// 1行の `targetList` の要素です。値を差し替えて想定外の形を作れます。
    struct Row {
        /// `id` の値。`nil` なら項目ごと省く。
        var id: String?
        /// `link` の値。`nil` なら項目ごと省く。
        var link: String?
    }

    /// 都道府県コード(1...47)から、`[a-z]+` だけの綴りを返します。群馬だけ実データと同じ `gumma` です。
    ///
    /// 責務: 実データと同様に、ローマ字から URL を組み立てられない綴りを再現します。
    static func slug(for number: Int) -> String {
        if number == 10 { return "gumma" }
        let digits = String(format: "%02d", number).map { Character(UnicodeScalar(UInt8(97 + Int(String($0))!))) }
        return "area" + String(digits)
    }

    /// 都道府県コードの行(`R01`〜`R47`)を返します。
    ///
    /// 責務: 公開の印と綴りから、正しいリンクの行を作ります。
    static func validRow(_ number: Int, stamp: String = stamp, type: String = "typeD") -> Row {
        Row(id: String(format: "R%02d", number), link: "/\(stamp)/\(type)_\(slug(for: number)).zip")
    }

    /// 47件すべてが正しい行を返します。
    static func fullRows(stamp: String = stamp) -> [Row] {
        (1...47).map { validRow($0, stamp: stamp) }
    }

    /// 1つの種別の項目を作ります。
    ///
    /// 責務: `type`・`title`・`targetMonth`・`releaseDay`・`targetList` を持つ辞書を返します。
    static func section(type: String, targetMonth: Any? = "2026年09月", rows: [Row]) -> [String: Any] {
        var object: [String: Any] = ["type": type, "title": "title", "releaseDay": "2026年11月01日"]
        if let targetMonth { object["targetMonth"] = targetMonth }
        object["targetList"] = rows.map { row -> [String: Any] in
            var item: [String: Any] = [:]
            if let id = row.id { item["id"] = id }
            if let link = row.link { item["link"] = link }
            return item
        }
        return object
    }

    /// 項目の配列を JSON のバイト列にします。
    ///
    /// 責務: ルートが配列の JSON を作ります。
    static func data(_ sections: [[String: Any]]) -> Data {
        guard let data = try? JSONSerialization.data(withJSONObject: sections) else {
            preconditionFailure("テスト用の JSON を作れません")
        }
        return data
    }

    /// typeB と typeD を並べた、実データと同じ形の一覧を返します(typeB が先)。
    static func realisticIndex(typeDRows: [Row] = fullRows(), targetMonth: Any? = "2026年09月") -> Data {
        data([
            section(type: "typeB", targetMonth: "2026年09月", rows: (1...47).map { validRow($0, type: "typeB") }),
            section(type: "typeD", targetMonth: targetMonth, rows: typeDRows)
        ])
    }
}
