import CoreGraphics
import Foundation
import GRDB
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import ProjectZD8

/// 永続化テストが共有する固定時計です。
final class PersistenceTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    /// 責務: 指定日時から始まる時計を生成します。
    init(_ start: Date = Date(epochMilliseconds: 1_700_000_000_000)) {
        current = start
    }

    /// 現在の日時です。
    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    /// 責務: 時計を進めます。
    func advance(by seconds: TimeInterval) {
        lock.lock()
        current = current.addingTimeInterval(seconds)
        lock.unlock()
    }
}

/// 永続化テストが共有するフィクスチャ生成関数です。
enum PersistenceTestFixtures {
    /// 責務: ミリ秒精度の基準日時を返します。
    static func date(_ offsetSeconds: TimeInterval = 0) -> Date {
        Date(epochMilliseconds: 1_700_000_000_000 + Int64(offsetSeconds * 1000))
    }

    /// 責務: テスト用の車両を生成します。
    static func vehicle(name: String = "ZD8", id: VehicleID = VehicleID(), photoID: PhotoID? = nil) -> Vehicle {
        Vehicle(
            id: id, vin: "JF1ZD8000000", obdIdentifier: "obd-1", name: name, manufacturer: "Subaru", engineModel: "FA24",
            powertrain: .combustion, energySources: [.gasolinePremium], tankCapacityLiters: 50, modelYear: 2024,
            note: "memo", photoID: photoID, createdAt: date(), modifiedAt: date(1)
        )
    }

    /// 責務: テスト用のPIDリクエストを生成します。
    static func request(_ pid: UInt8, service: UInt8 = 1) -> OBDPIDRequest {
        OBDPIDRequest(service: service, pid: pid)
    }

    /// 責務: テスト用のセッションを生成します。
    static func session(vehicleID: VehicleID, id: SessionID = SessionID(), startedAt: Date = date(10)) -> DriveSession {
        DriveSession(
            id: id, vehicleID: vehicleID, startedAt: startedAt, isDemo: false, adapterName: "ELM", adapterTransport: .bluetoothLowEnergy,
            platform: .mac, deviceID: "device", deviceName: "Mac15,6", appVersion: "1.0", appBuild: "1",
            pollingPolicyVersion: 1, modifiedAt: startedAt
        )
    }

    /// 責務: テスト用のセッションPIDを生成します。
    static func sessionPID(ordinal: Int, pid: UInt8) -> SessionPID {
        SessionPID(
            ordinal: ordinal, request: request(pid), header: ordinal == 0 ? 0x7E0 : nil, support: .supported,
            isCollectionEnabled: true, isFastGroup: ordinal == 0, definitionRevision: 1, requiredByteCount: 2,
            formula: "A", unit: "rpm", minimumValue: 0, maximumValue: 8000
        )
    }

    /// 責務: テスト用のサンプルを生成します。
    static func sample(_ sequence: Int64, outcome: SampleOutcome = .responded, payload: [UInt8] = [1, 2]) -> SessionSample {
        SessionSample(
            sequence: sequence, tick: Int(sequence / 2), elapsedMicroseconds: sequence * 1000,
            request: request(UInt8(12 + sequence % 2)), outcome: outcome, payload: Data(payload)
        )
    }

    /// 責務: テスト用の整備記録を生成します。
    static func maintenance(vehicleID: VehicleID, title: String = "oil", performedAt: Date = date(), photos: [PhotoID] = []) -> MaintenanceRecord {
        MaintenanceRecord(
            vehicleID: vehicleID, kind: .light, title: title, performedAt: performedAt, odometerKilometers: 1234.5, notes: "n",
            workItems: [MaintenanceWorkItem(component: .engineOil, operation: .replacement, productName: "5W-30", quantity: 4.5, unit: "L")],
            photos: photos.map { MaintenancePhoto(id: $0, caption: "c", capturedAt: date(5)) },
            fastenerGroups: [MaintenanceFastenerGroup(name: "cover", expectedCount: 4, removedCount: 4)],
            createdAt: date(), modifiedAt: date(2)
        )
    }

    /// 責務: 同期済みを表す `sync_records` 行を追加します。
    static func markSynced(_ database: AppDatabase, recordType: String, id: String) throws {
        try database.writer.write { db in
            try db.execute(sql: "INSERT INTO sync_records (recordType, recordID, syncedModifiedAt) VALUES (?, ?, 0)", arguments: [recordType, id])
        }
    }

    /// 責務: 非同期でない文脈でSQLを1文実行します。
    static func execute(_ database: AppDatabase, _ sql: String) throws {
        try database.writer.write { try $0.execute(sql: sql) }
    }

    /// 責務: 値を取り出します。`await` を含む式を渡せるよう自動クロージャにしません。
    static func unwrapped<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) throws -> T {
        try XCTUnwrap(value, file: file, line: line)
    }

    /// 責務: テーブルの行数を返します。
    static func count(_ database: AppDatabase, _ table: String, where condition: String = "1") throws -> Int {
        try database.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table) WHERE \(condition)") ?? 0
        }
    }

    /// 責務: 使い捨ての写真ディレクトリを持つストアを返し、テスト終了時に削除します。
    static func temporaryPhotoStore(_ testCase: XCTestCase) -> PhotoFileStore {
        let directory = FileManager.default.temporaryDirectory.appending(path: "photos-\(UUID().uuidString)", directoryHint: .isDirectory)
        testCase.addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return PhotoFileStore(directory: directory)
    }

    /// 責務: 指定サイズの単色画像をエンコードして返します。
    static func imageData(width: Int, height: Int, type: UTType = .png) throws -> Data {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(red: 0.2, green: 0.6, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }
}
