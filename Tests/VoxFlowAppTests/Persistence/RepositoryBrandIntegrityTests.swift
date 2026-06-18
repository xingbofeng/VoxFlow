import Foundation
import XCTest

final class RepositoryBrandIntegrityTests: XCTestCase {
    func testScannerFlagsConstructedDisallowedToken() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInputBrandIntegrity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let token = Self.disallowedProductTokens[0]
        let fileURL = directory.appendingPathComponent("sample.md")
        try "Do not ship \(token) in repository text.".write(to: fileURL, atomically: true, encoding: .utf8)

        let violations = try RepositoryTextScanner().violations(
            under: directory,
            disallowedTokens: Self.disallowedProductTokens
        )

        XCTAssertEqual(violations, ["sample.md:1"])
    }

    func testRepositoryTextFilesDoNotContainDisallowedProductReference() throws {
        let violations = try RepositoryTextScanner().violations(
            under: Self.repositoryRoot(),
            disallowedTokens: Self.disallowedProductTokens
        )

        XCTAssertTrue(
            violations.isEmpty,
            "Disallowed product reference found in:\n\(violations.joined(separator: "\n"))"
        )
    }

    private static let disallowedProductTokens = [
        ["Lazy", "Typer"].joined(),
        ["lazy", "typer"].joined(),
        ["Lazy", " Typer"].joined(),
        ["lazy", " typer"].joined(),
    ]

    private static func repositoryRoot() throws -> URL {
        var directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

        while directory.path != "/" {
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) {
                return directory
            }
            directory.deleteLastPathComponent()
        }

        throw NSError(
            domain: "RepositoryBrandIntegrityTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not locate Package.swift from current directory."]
        )
    }
}

private struct RepositoryTextScanner {
    private let ignoredDirectoryNames: Set<String> = [
        ".build",
        ".git",
        ".swiftpm",
        "dist",
        "DerivedData",
    ]

    private let textExtensions: Set<String> = [
        "css",
        "html",
        "json",
        "md",
        "plist",
        "sh",
        "swift",
        "txt",
        "xml",
        "yaml",
        "yml",
    ]

    private let extensionlessTextFiles: Set<String> = [
        "Makefile",
    ]

    func violations(under root: URL, disallowedTokens: [String]) throws -> [String] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var results: [String] = []

        for case let url as URL in enumerator {
            let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])

            if resourceValues.isDirectory == true, ignoredDirectoryNames.contains(url.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }

            guard resourceValues.isRegularFile == true, isTextFile(url) else {
                continue
            }

            let contents = try String(contentsOf: url, encoding: .utf8)
            for (index, line) in contents.components(separatedBy: .newlines).enumerated() {
                if disallowedTokens.contains(where: line.contains) {
                    results.append("\(relativePath(for: url, under: root)):\(index + 1)")
                }
            }
        }

        return results.sorted()
    }

    private func isTextFile(_ url: URL) -> Bool {
        if extensionlessTextFiles.contains(url.lastPathComponent) {
            return true
        }
        return textExtensions.contains(url.pathExtension.lowercased())
    }

    private func relativePath(for url: URL, under root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath + "/") else {
            return url.lastPathComponent
        }
        return String(filePath.dropFirst(rootPath.count + 1))
    }
}
