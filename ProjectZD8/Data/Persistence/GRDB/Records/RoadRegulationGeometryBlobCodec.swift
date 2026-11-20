import Foundation

/// 交通規制の形状を版つきの2進形式(BLOB)へ符号化・復号します。
///
/// 版1(リトルエンディアン): `[u8 版 = 1][u16 区間数]`。区間ごとに `[u8 役割][u32 点数][点数 × (i32 経度 × 1e7, i32 緯度 × 1e7)]`。
nonisolated struct RoadRegulationGeometryBlobCodec: Sendable {
    /// 現在の形式の版です。
    static let formatVersion: UInt8 = 1
    /// 度を保存の整数へ変える倍率です(1e-7 度単位)。
    static let coordinateScale = 10_000_000.0

    /// 形状を BLOB へ符号化します。
    ///
    /// 責務: 区間の役割と点列を版1の形式で書きます。区間数は u16、点数は u32 の上限で切り詰めます(実データでは届かない)。
    /// - Parameter geometry: 符号化する形状。
    /// - Returns: 版1の BLOB。
    func encode(_ geometry: RoadRegulationGeometry) -> Data {
        let parts = geometry.parts.prefix(Int(UInt16.max))
        var bytes: [UInt8] = [Self.formatVersion]
        Self.append(UInt16(parts.count), to: &bytes)
        for part in parts {
            let points = part.coordinates.prefix(Int(UInt32.max))
            bytes.append(part.role.rawValue)
            Self.append(UInt32(points.count), to: &bytes)
            for point in points {
                Self.append(Self.scaled(point.longitude), to: &bytes)
                Self.append(Self.scaled(point.latitude), to: &bytes)
            }
        }
        return Data(bytes)
    }

    /// BLOB から形状を復号します。
    ///
    /// 責務: 版1の形式を読み、版違い・途中で切れている・役割が不明・点数0・座標が範囲外・余りのバイトを拒否します。
    /// - Parameter data: 復号する BLOB。
    /// - Returns: 復号した形状。
    /// - Throws: 形式に合わない場合は `RoadRegulationRepositoryError.integrityConflict`。
    func decode(_ data: Data) throws -> RoadRegulationGeometry {
        var reader = RoadRegulationGeometryBlobReader(bytes: [UInt8](data))
        guard try reader.readUInt8() == Self.formatVersion else { throw RoadRegulationRepositoryError.integrityConflict }
        let partCount = try reader.readUInt16()
        var parts: [RoadRegulationGeometryPart] = []
        parts.reserveCapacity(Int(partCount))
        for _ in 0..<partCount {
            parts.append(try decodePart(from: &reader))
        }
        guard reader.isAtEnd else { throw RoadRegulationRepositoryError.integrityConflict }
        return RoadRegulationGeometry(parts: parts)
    }

    /// 1区間を読みます。
    ///
    /// 責務: 役割と点数を検証し、点列を座標へ復元します。
    /// - Parameter reader: 読み取り位置。
    /// - Returns: 復元した区間。
    /// - Throws: 役割が不明・点数0・途中で切れている・座標が範囲外は `.integrityConflict`。
    private func decodePart(from reader: inout RoadRegulationGeometryBlobReader) throws -> RoadRegulationGeometryPart {
        guard let role = RoadRegulationGeometryRole(rawValue: try reader.readUInt8()) else {
            throw RoadRegulationRepositoryError.integrityConflict
        }
        let pointCount = Int(try reader.readUInt32())
        guard pointCount > 0, pointCount <= reader.remainingCount / 8 else {
            throw RoadRegulationRepositoryError.integrityConflict
        }
        var coordinates: [GeoCoordinate] = []
        coordinates.reserveCapacity(pointCount)
        for _ in 0..<pointCount {
            let longitude = Double(try reader.readInt32()) / Self.coordinateScale
            let latitude = Double(try reader.readInt32()) / Self.coordinateScale
            guard let coordinate = GeoCoordinate(latitude: latitude, longitude: longitude) else {
                throw RoadRegulationRepositoryError.integrityConflict
            }
            coordinates.append(coordinate)
        }
        return RoadRegulationGeometryPart(role: role, coordinates: coordinates)
    }

    /// 度を 1e-7 度単位の整数へ丸めます。
    ///
    /// 責務: 有効な座標(±180 度以内)を最近傍の Int32 へ変換します。
    /// - Parameter degrees: 度。
    /// - Returns: 1e-7 度単位の整数。
    private static func scaled(_ degrees: Double) -> Int32 {
        Int32((degrees * coordinateScale).rounded(.toNearestOrAwayFromZero))
    }

    /// 固定長の整数をリトルエンディアンで追記します。
    ///
    /// 責務: 整数のバイト列を下位から順に書きます。
    /// - Parameters:
    ///   - value: 書く整数。
    ///   - bytes: 追記先。
    private static func append<Value: FixedWidthInteger>(_ value: Value, to bytes: inout [UInt8]) {
        withUnsafeBytes(of: value.littleEndian) { bytes.append(contentsOf: $0) }
    }
}
