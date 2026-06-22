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
        "VoxFlowProviderParakeet",
        "VoxFlowProviderOmnilingual",
        "VoxFlowProviderParaformer",
        "VoxFlowProviderFunASR",
        "VoxFlowProviderSenseVoice",
        "VoxFlowProviderWhisper",
        "VoxFlowProviderCloudCore",
        "VoxFlowProviderGroq",
        "VoxFlowProviderTencentCloud",
        "VoxFlowProviderAliyunDashScope",
        "VoxFlowTextProcessing",
        "VoxFlowTextInsertion",
        "VoxFlowLocalization",
        "VoxFlowFeatures",
        "VoxFlowDesignSystem",
        "VoxFlowInfrastructure",
        "VoxFlowScreenshotKit",
        "VoxFlowASRWorker",
    ]
    private let requiredTestTargets = [
        "VoxFlowAppTests",
        "VoxFlowASRCoreTests",
        "VoxFlowAudioTests",
        "VoxFlowDomainTests",
        "VoxFlowInfrastructureTests",
        "VoxFlowScreenshotKitTests",
        "VoxFlowProviderAppleTests",
        "VoxFlowProviderNVIDIATests",
        "VoxFlowProviderParaformerTests",
        "VoxFlowProviderCloudCoreTests",
        "VoxFlowProviderGroqTests",
        "VoxFlowProviderTencentCloudTests",
        "VoxFlowProviderAliyunDashScopeTests",
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
        let root = try Self.repositoryRoot()

        for target in requiredTargets {
            let directory = Self.sourceDirectory(for: target, root: root)
            var isDirectory: ObjCBool = false
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory) && isDirectory.boolValue,
                "\(Self.relativePath(for: directory, root: root)) must exist."
            )

            let swiftFiles = try Self.swiftFiles(in: directory)
            XCTAssertFalse(
                swiftFiles.isEmpty,
                "\(Self.relativePath(for: directory, root: root)) must contain at least one Swift file."
            )
        }
    }

    func testVoxFlowTargetsPlaceSwiftSourcesInsideResponsibilitySubdirectories() throws {
        let root = try Self.repositoryRoot()

        for target in requiredTargets where target != "VoxFlowApp" {
            let directory = Self.sourceDirectory(for: target, root: root)
            let rootSwiftFiles = try FileManager.default.contentsOfDirectory(atPath: directory.path)
                .filter { $0.hasSuffix(".swift") }
            XCTAssertTrue(
                rootSwiftFiles.isEmpty,
                "\(Self.relativePath(for: directory, root: root)) should organize Swift files in responsibility subdirectories, found root files: \(rootSwiftFiles)."
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
                "\(Self.relativePath(for: directory, root: root)) must contain at least one responsibility subdirectory with Swift source."
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

    func testVoxFlowAppDependsOnScreenshotKitTarget() throws {
        let root = try Self.repositoryRoot()
        let package = try String(
            contentsOf: root.appendingPathComponent("Package.swift"),
            encoding: .utf8
        )
        let appTargetStart = try XCTUnwrap(package.range(of: #"executableTarget\(\s*name: "VoxFlowApp""#, options: .regularExpression))
        let appTargetBody = package[appTargetStart.lowerBound...]
        let dependenciesStart = try XCTUnwrap(appTargetBody.range(of: "dependencies: ["))
        let dependenciesBody = appTargetBody[dependenciesStart.upperBound...]
        let dependenciesEnd = try XCTUnwrap(dependenciesBody.range(of: "],"))

        XCTAssertTrue(
            dependenciesBody[..<dependenciesEnd.lowerBound].contains(#""VoxFlowScreenshotKit""#),
            "VoxFlowApp target must depend on VoxFlowScreenshotKit so runtime adapters can import it."
        )
    }

    func testDedicatedVoxFlowTestTargetDirectoriesContainSwiftSource() throws {
        let root = try Self.repositoryRoot()

        for target in requiredTestTargets {
            let directory = Self.testDirectory(for: target, root: root)
            var isDirectory: ObjCBool = false
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory) && isDirectory.boolValue,
                "\(Self.relativePath(for: directory, root: root)) must exist."
            )
            guard isDirectory.boolValue else {
                continue
            }

            let swiftFiles = try FileManager.default.contentsOfDirectory(atPath: directory.path)
                .filter { $0.hasSuffix(".swift") }
            XCTAssertFalse(
                swiftFiles.isEmpty,
                "\(Self.relativePath(for: directory, root: root)) must contain at least one Swift file."
            )
        }
    }

    private static func sourceDirectory(for target: String, root: URL) -> URL {
        if target.hasPrefix("VoxFlowProvider") {
            return root.appendingPathComponent("Sources/VoxFlowProviders/\(target)", isDirectory: true)
        }
        return root.appendingPathComponent("Sources/\(target)", isDirectory: true)
    }

    private static func testDirectory(for target: String, root: URL) -> URL {
        if target.hasPrefix("VoxFlowProvider") {
            return root.appendingPathComponent("Tests/VoxFlowProviders/\(target)", isDirectory: true)
        }
        return root.appendingPathComponent("Tests/\(target)", isDirectory: true)
    }

    private static func relativePath(for url: URL, root: URL) -> String {
        let path = url.path
        let rootPath = root.path + "/"
        guard path.hasPrefix(rootPath) else { return path }
        return String(path.dropFirst(rootPath.count))
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
