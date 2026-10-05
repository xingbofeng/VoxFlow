import XCTest
@testable import VoxFlowModelStore

/// `ModelURLSessionDownloadTransport` 的断点续传落盘规则测试。
///
/// 该 transport 原先内联在 Qwen3 的下载器里，现已上移到 ModelStore 共享层，
/// 因此测试也一并迁移，断言与实现保持一致。
final class ModelURLSessionDownloadTransportTests: XCTestCase {
    func testCancelsOnlyActiveDownloadTask() throws {
        let source = try String(
            contentsOf: Self.repositoryRoot()
                .appendingPathComponent("Sources/VoxFlowModelStore/Download/ModelURLSessionDownloadTransport.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("activeDownloadTask?.cancel()"))
        XCTAssertFalse(source.contains("invalidateAndCancel()"))
        XCTAssertTrue(source.contains("defer { clearActiveDownloadState() }"))
    }

    func testAppendsValidPartialContentResponse() throws {
        let directory = try makeTemporaryDirectory()
        let destination = directory.appendingPathComponent("encoder.bin")
        let downloaded = directory.appendingPathComponent("download.tmp")
        try Data("he".utf8).write(to: destination)
        try Data("llo".utf8).write(to: downloaded)

        try ModelURLSessionDownloadTransport.moveDownloadedFile(
            from: downloaded,
            to: destination,
            resumeOffset: 2,
            response: httpResponse(statusCode: 206, headers: ["Content-Range": "bytes 2-4/5"]),
            fileManager: .default
        )

        XCTAssertEqual(try Data(contentsOf: destination), Data("hello".utf8))
    }

    func testOverwritesPartialWhenRangeRequestReturnsFullContent() throws {
        let directory = try makeTemporaryDirectory()
        let destination = directory.appendingPathComponent("encoder.bin")
        let downloaded = directory.appendingPathComponent("download.tmp")
        try Data("he".utf8).write(to: destination)
        try Data("hello".utf8).write(to: downloaded)

        try ModelURLSessionDownloadTransport.moveDownloadedFile(
            from: downloaded,
            to: destination,
            resumeOffset: 2,
            response: httpResponse(statusCode: 200),
            fileManager: .default
        )

        XCTAssertEqual(try Data(contentsOf: destination), Data("hello".utf8))
    }

    func testRejectsMismatchedContentRange() throws {
        let directory = try makeTemporaryDirectory()
        let destination = directory.appendingPathComponent("encoder.bin")
        let downloaded = directory.appendingPathComponent("download.tmp")
        try Data("he".utf8).write(to: destination)
        try Data("llo".utf8).write(to: downloaded)

        XCTAssertThrowsError(
            try ModelURLSessionDownloadTransport.moveDownloadedFile(
                from: downloaded,
                to: destination,
                resumeOffset: 2,
                response: httpResponse(statusCode: 206, headers: ["Content-Range": "bytes 0-4/5"]),
                fileManager: .default
            )
        ) { error in
            XCTAssertEqual(error as? ModelStoreDownloadError, .invalidContentRange("bytes 0-4/5"))
        }
    }

    private func httpResponse(statusCode: Int, headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://example.com/encoder.bin")!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func repositoryRoot() -> URL {
        var directory = URL(fileURLWithPath: #filePath)
        while directory.path != "/" {
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) {
                return directory
            }
            directory.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }
}
