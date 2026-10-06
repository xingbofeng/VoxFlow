import Foundation
import VoxFlowModelStore
@testable import VoxFlowProviderXASR
import XCTest

final class XASRManifestCatalogTests: XCTestCase {
    func testPinnedComponentsMatchVerifiedM0Assets() throws {
        let manifest = try XASRManifestCatalog.modelStoreManifest()
        let expected: [(String, Int64, String)] = [
            ("encoder-480ms.onnx", 592_968_361, "0c3454033d249081df124ddcd7adaf3deca07d0b999b26f2ee5d2475d37abc74"),
            ("decoder-480ms.onnx", 11_309_084, "3658368d274a5d5fd39a7ac20c46bed0ad9cfea1f0feddef30d5d89797c1f499"),
            ("joiner-480ms.onnx", 10_260_467, "03781c98165a2385024c9cecdd2b6b13310d81db23a62c7da420782c2915cf81"),
            ("tokens.txt", 58_806, "b818a60878b9aae978cbb8ad594acbd403d76d1af2e31ef4197c84e2dbdba27c"),
        ]
        let revision = "689ff18c584d29910da37b6fe904db0c1489c9d1"
        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertEqual(manifest.components.map(\.localPath), expected.map { $0.0 })
        for (component, asset) in zip(manifest.components, expected) {
            XCTAssertEqual(component.expectedSizeBytes, asset.1)
            XCTAssertEqual(component.sha256.rawValue, asset.2)
            XCTAssertEqual(component.providerID.rawValue, "xasr")
            XCTAssertEqual(component.modelID.rawValue, "xasr-zh-en-480ms")
            XCTAssertEqual(component.version, revision)
            XCTAssertEqual(component.runtimeVersion, "sherpa-onnx-1.13.3-xasr")
            XCTAssertEqual(component.requirement, .required)
            XCTAssertEqual(component.downloadURL.absoluteString,
                "https://huggingface.co/GilgameshWind/X-ASR-zh-en/resolve/\(revision)/deployment/models/chunk-480ms-model/\(asset.0)")
        }
        XCTAssertEqual(manifest.components.reduce(Int64(0)) { $0 + $1.expectedSizeBytes }, 614_596_718)
        XCTAssertEqual(XASRManifestCatalog.expectedDownloadBytes, 614_596_718)
        XCTAssertEqual(XASRManifestCatalog.modelInstallKey,
            ModelInstallKey(modelID: .init(rawValue: "xasr-zh-en-480ms"), version: revision))
    }

    func testEveryComponentCarriesFrozenHardwareAndWeightLicenseMetadata() throws {
        let manifest = try XASRManifestCatalog.modelStoreManifest()
        XCTAssertEqual(manifest.components.count, 4)
        for component in manifest.components {
            XCTAssertEqual(component.supportedArchitectures, [.arm64])
            XCTAssertEqual(component.minimumOSVersion, "15.0")
            XCTAssertEqual(component.minimumMemoryBytes, 8 * 1_024 * 1_024 * 1_024)
            XCTAssertEqual(component.license.name, "Apache-2.0")
            XCTAssertEqual(component.license.url?.absoluteString,
                "https://huggingface.co/GilgameshWind/X-ASR-zh-en/blob/689ff18c584d29910da37b6fe904db0c1489c9d1/README.md")
        }
    }
}
