import CloudKit
import XCTest
@testable import ProjectZD8

/// スキーマ定義ファイル(`RevTorqueInsightCloudKitSchema.ckdb`)が、マッパーの作るレコードと一致することを確認します(コンテナ不要)。
///
/// 定義の正はマッパーです。マッパーへフィールドを足したり型を変えたりした時に、
/// スキーマ定義ファイルの更新漏れをここで検出します。
final class CloudKitSchemaDefinitionTests: XCTestCase {
    /// 定義ファイルの1フィールドです。
    private struct SchemaField: Equatable, CustomStringConvertible {
        let type: String
        let options: [String]
        var description: String { ([type] + options).joined(separator: " ") }
    }

    /// 責務: 全オプションを埋めた各同期レコードの、フィールド名と型の対応がスキーマ定義と一致することを確認します。
    func testSchemaMatchesFieldsWrittenByMappers() throws {
        let schema = try loadSchema()
        let expected = try fieldTypesWrittenByMappers()

        XCTAssertEqual(Set(schema.keys), Set(expected.keys), "スキーマ定義のレコード型がコードと一致しません")
        for (recordType, fields) in expected {
            let defined = try XCTUnwrap(schema[recordType], recordType)
            XCTAssertEqual(
                defined.mapValues(\.type), fields,
                "\(recordType) のフィールドがコードと一致しません"
            )
        }
    }

    /// 責務: 同期で使う全てのレコード型がスキーマ定義にあることを確認します。
    func testSchemaCoversEverySyncedRecordType() throws {
        let schema = try loadSchema()
        let synced = Set(SyncRecordType.allCases.map(\.rawValue) + [CloudKitArchiveRecordMapper.recordType])
        XCTAssertEqual(Set(schema.keys), synced)
    }

    /// 責務: 端末ローカルの列がスキーマ定義に入っていないことを確認します。
    func testSchemaExcludesLocalOnlyColumns() throws {
        let schema = try loadSchema()
        for (recordType, fields) in schema {
            XCTAssertNil(fields["rawAvailability"], recordType)
            XCTAssertNil(fields["deletedAt"], recordType)
        }
    }

    /// 責務: CKQuery を使わない設計のため、インデックス指定もGRANTも持たないことを確認します。
    ///
    /// 照会を追加する時は、この確認と定義ファイルの両方を意図して変更します。
    func testSchemaDeclaresNoIndexes() throws {
        let schema = try loadSchema()
        for (recordType, fields) in schema {
            for (name, field) in fields {
                XCTAssertTrue(field.options.isEmpty, "\(recordType).\(name) に \(field) が指定されています")
                XCTAssertFalse(name.hasPrefix("_"), "\(recordType) にシステムフィールド \(name) が指定されています")
            }
        }
    }

    // MARK: - コード側

    /// 責務: マッパーで全フィールドを埋めたレコードを作り、型ごとにフィールド名とスキーマ言語の型名を返します。
    private func fieldTypesWrittenByMappers() throws -> [String: [String: String]] {
        let mapper = CloudKitRecordMapper()
        let vehicleID = SyncTestFixtures.newID()
        var vehicle = SyncTestFixtures.vehicle(id: vehicleID, photoID: SyncTestFixtures.newID())
        vehicle.obdIdentifier = "OBD-1"
        let fileURL = FileManager.default.temporaryDirectory.appending(path: "schema-check.bin")

        let outgoing: [SyncOutgoingRecord] = [
            SyncOutgoingRecord(payload: .vehicle(vehicle), systemFields: nil),
            SyncOutgoingRecord(payload: .maintenanceRecord(SyncTestFixtures.maintenance(vehicleID: vehicleID)), systemFields: nil),
            SyncOutgoingRecord(payload: .photo(SyncTestFixtures.photo(vehicleID: vehicleID)), systemFields: nil, photoFileURL: fileURL),
            SyncOutgoingRecord(payload: .driveSession(SyncTestFixtures.session(vehicleID: vehicleID, archiveDigest: "ab")), systemFields: nil),
        ]
        var records = outgoing.map(mapper.record(for:))
        records.append(CloudKitArchiveRecordMapper().record(sessionID: SyncTestFixtures.newID(), vehicleID: vehicleID, digest: "ab", fileURL: fileURL))

        var result: [String: [String: String]] = [:]
        for record in records {
            var fields: [String: String] = [:]
            for key in record.allKeys() {
                fields[key] = schemaType(of: try XCTUnwrap(record[key]), key: "\(record.recordType).\(key)")
            }
            result[record.recordType] = fields
        }
        return result
    }

    /// 責務: レコードの値の型をスキーマ言語の型名へ対応させます。
    private func schemaType(of value: any CKRecordValueProtocol, key: String) -> String {
        switch value {
        case is CKAsset: return "ASSET"
        case is CKRecord.Reference: return "REFERENCE"
        case is String: return "STRING"
        case is Data: return "BYTES"
        case let number as NSNumber:
            // NSNumber は Int64 / Double の相互キャストが成功するため、格納時の型符号で区別します。
            switch String(cString: number.objCType) {
            case "q", "l", "i", "s", "c": return "INT64"
            case "d", "f": return "DOUBLE"
            case let code:
                XCTFail("\(key) の数値型符号 \(code) は未対応です")
                return "UNKNOWN"
            }
        default:
            XCTFail("\(key) の値の型 \(type(of: value)) は未対応です")
            return "UNKNOWN"
        }
    }

    // MARK: - 定義ファイル側

    /// 責務: テストバンドルの定義ファイルを読み、型ごとのフィールド定義を返します。
    private func loadSchema() throws -> [String: [String: SchemaField]] {
        let url = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "RevTorqueInsightCloudKitSchema", withExtension: "ckdb"),
            "定義ファイルがテストバンドルにありません"
        )
        return try parseSchema(String(contentsOf: url, encoding: .utf8))
    }

    /// 責務: CloudKit Schema Language のうち、このファイルが使う範囲(DEFINE SCHEMA と RECORD TYPE)を解釈します。
    ///
    /// 想定外の構文(CREATE ROLE、GRANT、未知の型・オプション、名前の重複)は失敗にします。
    private func parseSchema(_ source: String) throws -> [String: [String: SchemaField]] {
        let text = source
            .replacing(/\/\*[\s\S]*?\*\//, with: " ")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                var line = Substring(line)
                if let range = line.firstRange(of: "//") { line = line[..<range.lowerBound] }
                if let range = line.firstRange(of: "--") { line = line[..<range.lowerBound] }
                return String(line)
            }
            .joined(separator: "\n")

        let header = try XCTUnwrap(text.firstRange(of: /^\s*DEFINE\s+SCHEMA\b/), "DEFINE SCHEMA がありません")
        let body = text[header.upperBound...]

        let primitiveTypes: Set<String> = ["ASSET", "BYTES", "DOUBLE", "INT64", "LOCATION", "REFERENCE", "STRING", "TIMESTAMP"]
        let fieldOptions: Set<String> = ["QUERYABLE", "SORTABLE", "SEARCHABLE"]
        var schema: [String: [String: SchemaField]] = [:]

        let statements = body.split(separator: ";").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        for statement in statements {
            let match = try XCTUnwrap(
                statement.wholeMatch(of: /RECORD\s+TYPE\s+([A-Za-z][A-Za-z0-9_]*)\s*\(([\s\S]*)\)/),
                "解釈できない文です: \(statement)"
            )
            let typeName = String(match.1)
            XCTAssertNil(schema[typeName], "\(typeName) が重複しています")
            var fields: [String: SchemaField] = [:]
            for entry in match.2.split(separator: ",") {
                let tokens = entry.split(whereSeparator: \.isWhitespace).map(String.init)
                guard let name = tokens.first else { continue }
                XCTAssertNotEqual(name.uppercased(), "GRANT", "\(typeName) に GRANT があります")
                XCTAssertGreaterThanOrEqual(tokens.count, 2, "\(typeName).\(name) に型がありません")
                let fieldName = name.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                let type = tokens.count > 1 ? tokens[1] : ""
                XCTAssertTrue(primitiveTypes.contains(type), "\(typeName).\(fieldName) の型 \(type) は想定外です")
                let options = Array(tokens.dropFirst(2))
                XCTAssertTrue(options.allSatisfy(fieldOptions.contains), "\(typeName).\(fieldName) のオプション \(options) は想定外です")
                XCTAssertNil(fields[fieldName], "\(typeName).\(fieldName) が重複しています")
                fields[fieldName] = SchemaField(type: type, options: options)
            }
            schema[typeName] = fields
        }
        return schema
    }
}
