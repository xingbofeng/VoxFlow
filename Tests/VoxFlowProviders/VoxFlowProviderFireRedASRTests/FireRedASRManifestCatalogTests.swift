import Foundation
import VoxFlowModelStore
@testable import VoxFlowProviderFireRedASR
import XCTest

final class FireRedASRManifestCatalogTests: XCTestCase {
    func testInstalledManifestDescribesTheThreeRequiredArtifacts() {
        let manifest = FireRedASRManifestCatalog.installedManifest()

        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertEqual(
            manifest.components.map(\.localPath).sorted(),
            FireRedASRModel.requiredPaths.sorted()
        )
        XCTAssertTrue(manifest.components.allSatisfy { $0.requirement == .required })
    }

    func testInstalledManifestPinsMeasuredSizeAndDigestPerComponent() {
        let manifest = FireRedASRManifestCatalog.installedManifest()
        let expected = Dictionary(
            uniqueKeysWithValues: FireRedASRModel.componentDigests.map {
                ($0.path, (bytes: $0.bytes, sha256: $0.sha256))
            }
        )

        for component in manifest.components {
            let digest = expected[component.localPath]
            XCTAssertNotNil(digest, "unexpected component \(component.localPath)")
            XCTAssertEqual(component.expectedSizeBytes, digest?.bytes)
            XCTAssertEqual(component.sha256.rawValue, digest?.sha256)
            XCTAssertEqual(component.sha256.rawValue.count, 64)
        }
    }

    func testInstalledBytesMatchesTheComponentSum() {
        let manifest = FireRedASRManifestCatalog.installedManifest()
        let sum = manifest.components.reduce(Int64(0)) { $0 + $1.expectedSizeBytes }

        XCTAssertEqual(FireRedASRManifestCatalog.installedBytes, sum)
        XCTAssertEqual(sum, FireRedASRModel.installedBytes)
    }

    func testRequiredDiskBytesCoversArchiveAndUnpackedResultSimultaneously() {
        // 下载与解包会同时存在，门槛必须是两者之和；只取较大者会在解包阶段空间耗尽。
        XCTAssertEqual(
            FireRedASRManifestCatalog.requiredDiskBytes,
            FireRedASRModel.archiveBytes + FireRedASRModel.installedBytes
        )
        XCTAssertGreaterThan(
            FireRedASRManifestCatalog.requiredDiskBytes,
            FireRedASRModel.archiveBytes
        )
    }

    func testArchiveManifestDescribesTheTarballItself() throws {
        let manifest = FireRedASRManifestCatalog.archiveManifest()
        let component = try XCTUnwrap(manifest.components.first)

        XCTAssertEqual(manifest.components.count, 1)
        XCTAssertEqual(component.localPath, FireRedASRModel.archiveName)
        XCTAssertEqual(component.downloadURL, FireRedASRModel.archiveURL)
        XCTAssertEqual(component.expectedSizeBytes, FireRedASRModel.archiveBytes)
        XCTAssertEqual(component.sha256.rawValue, FireRedASRModel.archiveSHA256)
    }

    func testArchiveComponentIsNotPartOfTheInstalledLayout() {
        // 归档会被解包后删除；如果它出现在安装清单里，安装目录会多出一个 838 MB 的 tar.bz2。
        let installedPaths = Set(FireRedASRManifestCatalog.installedManifest().components.map(\.localPath))

        XCTAssertFalse(installedPaths.contains(FireRedASRModel.archiveName))
    }

    func testManifestMetadataSatisfiesTheSharedValidatorRequirements() throws {
        // ModelIntegrityValidator 会对空 providerID/modelID/version/runtimeVersion/localPath/license.name 报
        // invalidMetadata。这里直接跑一次真校验，避免清单漏字段只能等到用户下载时才发现。
        let manifest = FireRedASRManifestCatalog.installedManifest()
        let emptyRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: emptyRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: emptyRoot) }

        let report = try ModelIntegrityValidator().validate(
            manifest: manifest,
            installedRoot: emptyRoot,
            runtimeVersion: FireRedASRManifestCatalog.runtimeVersion
        )

        let metadataIssues = report.issues.filter {
            if case .invalidMetadata = $0 { return true }
            return false
        }
        XCTAssertEqual(metadataIssues, [])
        let runtimeIssues = report.issues.filter {
            if case .runtimeVersionMismatch = $0 { return true }
            return false
        }
        XCTAssertEqual(runtimeIssues, [])
    }

    func testInstallKeyAndVersionFollowTheModelLayout() {
        XCTAssertEqual(FireRedASRManifestCatalog.version, FireRedASRModel.directoryName)
        XCTAssertEqual(FireRedASRManifestCatalog.modelInstallKey.modelID.rawValue, "fireredasr-aed-int8")
        XCTAssertEqual(FireRedASRManifestCatalog.modelInstallKey.version, FireRedASRModel.directoryName)
    }
}
