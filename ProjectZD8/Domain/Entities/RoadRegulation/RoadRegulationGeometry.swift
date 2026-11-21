import Foundation

/// 交通規制の形状(規制場所・一時停止の進入方向・除外の区間の集まり)です。
nonisolated struct RoadRegulationGeometry: Equatable, Sendable {
    /// 形状を構成する区間(取り込んだ順)。
    let parts: [RoadRegulationGeometryPart]

    /// 規制場所の区間ごとの点の列です。
    var mainParts: [[GeoCoordinate]] {
        coordinates(of: .main)
    }

    /// 一時停止の進入方向の点(区間をまたいで順に並べたもの)です。
    var approachPoints: [GeoCoordinate] {
        coordinates(of: .approach).flatMap { $0 }
    }

    /// 除外区間・区域の区間ごとの点の列です。
    var exclusionParts: [[GeoCoordinate]] {
        coordinates(of: .exclusion)
    }

    /// 規制場所と進入方向の点をすべて含む外接矩形です(除外は含めません)。点が無ければ `nil`。
    var boundingBox: GeoBoundingBox? {
        GeoBoundingBox(enclosing: mainParts.flatMap { $0 } + approachPoints)
    }

    /// 指定した役割の区間の点の列を返します。
    ///
    /// 責務: 区間を役割で絞り込み、元の順序を保って返します。
    /// - Parameter role: 取り出す役割。
    /// - Returns: 区間ごとの点の列。
    private func coordinates(of role: RoadRegulationGeometryRole) -> [[GeoCoordinate]] {
        parts.filter { $0.role == role }.map(\.coordinates)
    }
}
