import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import ProjectZD8

/// `VehicleImageDecoder` のデコード・縮小・フォールバック前提の検証。
final class VehicleImageDecoderTests: XCTestCase {
    private func makePNG(width: Int, height: Int) throws -> Data {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0, green: 0.5, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    func testDecodesValidImageAndDownscalesToMaxPixelSize() throws {
        let image = try VehicleImageDecoder.decode(try makePNG(width: 400, height: 200), maxPixelSize: 100)
        XCTAssertEqual(max(image.width, image.height), 100)
        XCTAssertEqual(image.width, 100)
        XCTAssertEqual(image.height, 50)
    }

    func testEmptyDataThrowsEmptyData() {
        XCTAssertThrowsError(try VehicleImageDecoder.decode(Data())) {
            XCTAssertEqual($0 as? VehicleImageDecodingError, .emptyData)
        }
    }

    func testGarbageDataThrowsUndecodable() {
        XCTAssertThrowsError(try VehicleImageDecoder.decode(Data([0, 1, 2, 3, 4]))) {
            XCTAssertEqual($0 as? VehicleImageDecodingError, .undecodable)
        }
    }

    func testMonogramUsesUpToTwoInitials() {
        XCTAssertEqual(VehicleImageDecoder.monogram(from: "Honda S2000"), "HS")
        XCTAssertEqual(VehicleImageDecoder.monogram(from: "  zd8 "), "Z")
        XCTAssertEqual(VehicleImageDecoder.monogram(from: "a b c"), "AB")
        XCTAssertEqual(VehicleImageDecoder.monogram(from: ""), "")
        XCTAssertEqual(VehicleImageDecoder.monogram(from: "トヨタ 86"), "ト8")
    }
}
