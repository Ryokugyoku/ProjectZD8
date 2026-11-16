import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import ProjectZD8

/// `AppGroupSessionActivityVehiclePhotoStore` の保存・保存先・上書き・削除・失敗を、注入した一時ディレクトリで検証します。
///
/// 仕様: U5 受け入れ条件 10(B14)。一時ディレクトリはテストごとに作り、終了時に消します。
@MainActor
final class AppGroupSessionActivityVehiclePhotoStoreTests: XCTestCase {
    /// テストごとの一時ディレクトリです。
    private var root: URL!
    /// 写真ディレクトリ(まだ作られていない入れ子の場所)です。
    private var directory: URL!
    /// 写真の持ち主の車両IDです。
    private let vehicleID = VehicleID(rawValue: UUID(uuidString: "70000000-0000-0000-0000-000000000007")!)

    /// 責務: 一時ディレクトリを用意します(写真ディレクトリ自体は作りません)。
    override func setUp() async throws {
        try await super.setUp()
        root = FileManager.default.temporaryDirectory.appendingPathComponent("PhotoStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        directory = root.appendingPathComponent("nested/SessionActivityVehiclePhotos", isDirectory: true)
    }

    /// 責務: 一時ディレクトリを消します。
    override func tearDown() async throws {
        if let root { try? FileManager.default.removeItem(at: root) }
        root = nil
        directory = nil
        try await super.tearDown()
    }

    /// 一時ディレクトリへ保存する検証対象を作ります。
    ///
    /// 責務: 写真ディレクトリの取得元を注入します。
    private func makeStore() -> AppGroupSessionActivityVehiclePhotoStore {
        let directory = directory!
        return AppGroupSessionActivityVehiclePhotoStore(directoryURL: { directory })
    }

    /// 指定の大きさの PNG データを作ります。
    ///
    /// 責務: 単色のビットマップを PNG へ書き出します。
    /// - Parameters:
    ///   - width: 幅のピクセル数。
    ///   - height: 高さのピクセル数。
    /// - Returns: PNG データ。
    private func pngData(width: Int, height: Int) throws -> Data {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0, green: 0.7, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    /// 写真ディレクトリ内のファイル名です(並べ替え済み)。
    private func storedFileNames() throws -> [String] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    }

    /// 保存すると、無かった写真ディレクトリを作り、車両IDを先頭に持つ JPEG を唯一のファイルとして置き、そのファイル名を返します。
    ///
    /// 責務: 返したファイル名・置き場所・拡張子・JPEG であること・長辺480ピクセル以下への縮小を確認します。
    func testReplaceStoresSingleDownscaledJPEG() throws {
        let fileName = try makeStore().replacePhoto(with: pngData(width: 1_200, height: 600), for: vehicleID)

        XCTAssertEqual(try storedFileNames(), [fileName])
        XCTAssertTrue(fileName.hasPrefix(vehicleID.rawValue.uuidString + "-"))
        XCTAssertTrue(fileName.hasSuffix(".jpg"))
        let url = directory.appendingPathComponent(fileName)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetType(source) as String?, UTType.jpeg.identifier)
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let width = try XCTUnwrap(properties[kCGImagePropertyPixelWidth] as? Int)
        let height = try XCTUnwrap(properties[kCGImagePropertyPixelHeight] as? Int)
        XCTAssertLessThanOrEqual(max(width, height), AppGroupSessionActivityVehiclePhotoStore.maximumPixelLength)
        XCTAssertEqual(AppGroupSessionActivityVehiclePhotoStore.maximumPixelLength, 480)
    }

    /// 長辺が上限以下の写真は拡大しません。
    ///
    /// 責務: 200×100 の写真が長辺200ピクセル以下で保存されることを確認します。
    func testSmallPhotoIsNotUpscaled() throws {
        let fileName = try makeStore().replacePhoto(with: pngData(width: 200, height: 100), for: vehicleID)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(directory.appendingPathComponent(fileName) as CFURL, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertLessThanOrEqual(try XCTUnwrap(properties[kCGImagePropertyPixelWidth] as? Int), 200)
    }

    /// 保存し直すと、前の写真を消して新しい名前の写真だけを残します(表示が古い画像を使い回さないため)。
    ///
    /// 責務: 2回の保存でファイル名が異なり、ディレクトリ内が2回目のファイルだけになることを確認します。
    func testReplaceOverwritesPreviousPhoto() throws {
        let store = makeStore()
        let first = try store.replacePhoto(with: pngData(width: 100, height: 100), for: vehicleID)
        let second = try store.replacePhoto(with: pngData(width: 100, height: 100), for: vehicleID)

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try storedFileNames(), [second])
    }

    /// 画像として読めないデータは `undecodableImage` で失敗します。
    ///
    /// 責務: 画像でないバイト列の保存が型付きの失敗になることを確認します。
    func testUndecodableDataFails() {
        XCTAssertThrowsError(try makeStore().replacePhoto(with: Data([0x00, 0x01, 0x02]), for: vehicleID)) {
            XCTAssertEqual($0 as? AppGroupSessionActivityVehiclePhotoStoreError, .undecodableImage)
        }
    }

    /// 共有コンテナが使えない時は、保存も削除も `containerUnavailable` で失敗します。
    ///
    /// 責務: 写真ディレクトリの取得元が `nil` を返す時の2つの操作を確認します。
    func testContainerUnavailableFailsBothOperations() throws {
        let store = AppGroupSessionActivityVehiclePhotoStore(directoryURL: { nil })
        let photo = try pngData(width: 10, height: 10)
        XCTAssertThrowsError(try store.replacePhoto(with: photo, for: vehicleID)) {
            XCTAssertEqual($0 as? AppGroupSessionActivityVehiclePhotoStoreError, .containerUnavailable)
        }
        XCTAssertThrowsError(try store.removeAllPhotos()) {
            XCTAssertEqual($0 as? AppGroupSessionActivityVehiclePhotoStoreError, .containerUnavailable)
        }
    }

    /// 削除は写真ディレクトリ内のファイルをすべて消し、ディレクトリが無ければ何もせず成功します。
    ///
    /// 責務: ディレクトリなしの削除が成功し、保存後の削除で空になることを確認します。
    func testRemoveAllPhotos() throws {
        let store = makeStore()
        XCTAssertNoThrow(try store.removeAllPhotos())

        _ = try store.replacePhoto(with: pngData(width: 50, height: 50), for: vehicleID)
        try Data([1]).write(to: directory.appendingPathComponent("other.bin"))
        try store.removeAllPhotos()

        XCTAssertEqual(try storedFileNames(), [])
    }
}
