import Foundation
import XCTest

final class SwiftPMTargetSkeletonTests: XCTestCase {
    private let requiredTargets = [
        "VoxFlowApp",
        "VoxFlowDomain",
        "VoxFlowAudio",
        "VoxFlowASRCore",
        "VoxFlowModelStore",
        "VoxFlowProviderApple",
        "VoxFlowProviderQwen3",
        "VoxFlowProviderNVIDIA",
        "VoxFlowProviderParaformer",
        "VoxFlowProviderFunASR",
        "VoxFlowProviderSenseVoice",
        "VoxFlowProviderWhisper",
        "VoxFlowTextProcessing",
        "VoxFlowTextInsertion",
        "VoxFlowLocalization",
        "VoxFlowFeatures",
        "VoxFlowDesignSystem",
        "VoxFlowInfrastructure",
        "VoxFlowASRWorker",
    ]
    private let requiredTestTargets = [
        "VoxFlowAppTests",
        "VoxFlowASRCoreTests",
        "VoxFlowAudioTests",
        "VoxFlowDomainTests",
        "VoxFlowInfrastructureTests",
        "VoxFlowProviderAppleTests",
        "VoxFlowProviderNVIDIATests",
        "VoxFlowProviderParaformerTests",
    ]

    func testPackageDeclaresVoxFlow2TargetSkeleton() throws {
        let root = try Self.repositoryRoot()
        let package = try String(
            contentsOf: root.appendingPathComponent("Package.swift"),
            encoding: .utf8
        )

        for target in requiredTargets {
            XCTAssertTrue(
                package.contains("name: \"\(target)\""),
                "Package.swift must declare target \(target)."
            )
        }
    }

    func testPackageDoesNotDeclareRemovedLegacyProviderTargets() throws {
        let root = try Self.repositoryRoot()
        let package = try String(
            contentsOf: root.appendingPathComponent("Package.swift"),
            encoding: .utf8
        )
        let sourceRoot = root.appendingPathComponent("Sources", isDirectory: true)
        let removedTargets: [String] = []

        for target in removedTargets {
            XCTAssertFalse(
                package.contains("name: \"\(target)\""),
                "Package.swift must not declare removed target \(target)."
            )
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: sourceRoot.appendingPathComponent(target, isDirectory: true).path),
                "Sources/\(target) must be removed with the target declaration."
            )
        }
    }

    func testTargetSkeletonDirectoriesContainSwiftSource() throws {
        let sourceRoot = try Self.repositoryRoot().appendingPathComponent("Sources", isDirectory: true)

        for target in requiredTargets {
            let directory = sourceRoot.appendingPathComponent(target, isDirectory: true)
            var isDirectory: ObjCBool = false
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory) && isDirectory.boolValue,
                "Sources/\(target) must exist."
            )

            let swiftFiles = try Self.swiftFiles(in: directory)
            XCTAssertFalse(swiftFiles.isEmpty, "Sources/\(target) must contain at least one Swift file.")
        }
    }

    func testVoxFlowTargetsPlaceSwiftSourcesInsideResponsibilitySubdirectories() throws {
        let sourceRoot = try Self.repositoryRoot().appendingPathComponent("Sources", isDirectory: true)

        for target in requiredTargets where target != "VoxFlowApp" {
            let directory = sourceRoot.appendingPathComponent(target, isDirectory: true)
            let rootSwiftFiles = try FileManager.default.contentsOfDirectory(atPath: directory.path)
                .filter { $0.hasSuffix(".swift") }
            XCTAssertTrue(
                rootSwiftFiles.isEmpty,
                "Sources/\(target) should organize Swift files in responsibility subdirectories, found root files: \(rootSwiftFiles)."
            )

            let hasSwiftSubdirectory = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            .contains { child in
                (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                    && ((try? Self.swiftFiles(in: child).isEmpty) == false)
            }
            XCTAssertTrue(
                hasSwiftSubdirectory,
                "Sources/\(target) must contain at least one responsibility subdirectory with Swift source."
            )
        }
    }

    func testPackageDeclaresDedicatedVoxFlowTestTargets() throws {
        let root = try Self.repositoryRoot()
        let package = try String(
            contentsOf: root.appendingPathComponent("Package.swift"),
            encoding: .utf8
        )

        for target in requiredTestTargets {
            XCTAssertTrue(
                package.contains("name: \"\(target)\""),
                "Package.swift must declare test target \(target)."
            )
        }
    }

    func testDedicatedVoxFlowTestTargetDirectoriesContainSwiftSource() throws {
        let testRoot = try Self.repositoryRoot().appendingPathComponent("Tests", isDirectory: true)

        for target in requiredTestTargets {
            let directory = testRoot.appendingPathComponent(target, isDirectory: true)
            var isDirectory: ObjCBool = false
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory) && isDirectory.boolValue,
                "Tests/\(target) must exist."
            )
            guard isDirectory.boolValue else {
                continue
            }

            let swiftFiles = try FileManager.default.contentsOfDirectory(atPath: directory.path)
                .filter { $0.hasSuffix(".swift") }
            XCTAssertFalse(swiftFiles.isEmpty, "Tests/\(target) must contain at least one Swift file.")
        }
    }

    private static func repositoryRoot() throws -> URL {
        var directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        while directory.path != "/" {
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) {
                return directory
            }
            directory.deleteLastPathComponent()
        }
        throw NSError(
            domain: "SwiftPMTargetSkeletonTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not locate Package.swift from current directory."]
        )
    }

    private static func swiftFiles(in directory: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return try enumerator.compactMap { item in
            guard let url = item as? URL else { return nil }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            return values.isRegularFile == true && url.pathExtension == "swift" ? url : nil
        }
    }
}
