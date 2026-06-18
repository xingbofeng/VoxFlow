import AppKit
import XCTest

final class AppIconAssetTests: XCTestCase {
    func testGeneratedIconsetKeepsAllFourCornersTransparent() throws {
        let iconset = try Self.repositoryRoot().appendingPathComponent("Resources/AppIcon.iconset")
        let files = try FileManager.default.contentsOfDirectory(
            at: iconset,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "png" }

        XCTAssertFalse(files.isEmpty)
        for file in files {
            let image = try XCTUnwrap(NSImage(contentsOf: file), file.path)
            let bitmap = try XCTUnwrap(
                NSBitmapImageRep(
                    data: try XCTUnwrap(image.tiffRepresentation)
                ),
                file.path
            )
            let points = [
                (0, 0),
                (bitmap.pixelsWide - 1, 0),
                (0, bitmap.pixelsHigh - 1),
                (bitmap.pixelsWide - 1, bitmap.pixelsHigh - 1),
            ]
            for (x, y) in points {
                XCTAssertLessThanOrEqual(
                    bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 1,
                    0.02,
                    "\(file.lastPathComponent) has an opaque corner at \(x),\(y)"
                )
            }
        }
    }

    private static func repositoryRoot() throws -> URL {
        var directory = URL(fileURLWithPath: #filePath)
        while directory.path != "/" {
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) {
                return directory
            }
            directory.deleteLastPathComponent()
        }
        throw NSError(
            domain: "AppIconAssetTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not locate Package.swift from test file path."]
        )
    }
}
