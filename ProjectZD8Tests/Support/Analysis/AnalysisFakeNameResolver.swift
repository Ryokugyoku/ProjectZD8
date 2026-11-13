import Foundation
@testable import ProjectZD8

/// 分析テスト用の名称解決です。キーに接頭辞を付けて返します。
nonisolated struct AnalysisFakeNameResolver: AnalysisPIDNamePort {
    func displayName(forKey key: String) -> String { "name:" + key }
}
