import AppKit
import XCTest

final class AppIconAssetTests: XCTestCase {
    func testGeneratedIconsetKeepsAllFourCornersTransparent() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let iconset = repositoryRoot.appendingPathComponent("Resources/AppIcon.iconset")
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
}
