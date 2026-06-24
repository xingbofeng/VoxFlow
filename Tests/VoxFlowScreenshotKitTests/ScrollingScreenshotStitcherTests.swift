import CoreGraphics
import XCTest
@testable import VoxFlowScreenshotKit

final class ScrollingScreenshotStitcherTests: XCTestCase {
    func testAppendingDownwardFrameAddsOnlyNewBottomRows() throws {
        let first = makeImage(rows: [
            [.red, .green],
            [.blue, .yellow],
            [.cyan, .magenta],
        ])
        let second = makeImage(rows: [
            [.blue, .yellow],
            [.cyan, .magenta],
            [.black, .white],
        ])
        let stitcher = ScrollingScreenshotStitcher(shiftDetector: { _, _ in -1 })

        _ = stitcher.start(with: first)
        let stitched = try XCTUnwrap(stitcher.append(second))

        XCTAssertEqual(stitched.width, 2)
        XCTAssertEqual(stitched.height, 4)
        XCTAssertEqual((0..<2).map { pixel(atX: $0, y: 0, in: stitched) }, [.red, .green])
        XCTAssertEqual((0..<2).map { pixel(atX: $0, y: 1, in: stitched) }, [.blue, .yellow])
        XCTAssertEqual((0..<2).map { pixel(atX: $0, y: 2, in: stitched) }, [.cyan, .magenta])
        XCTAssertEqual((0..<2).map { pixel(atX: $0, y: 3, in: stitched) }, [.black, .white])
    }

    func testAppendReturnsNilWhenShiftIsTooSmall() {
        let image = makeImage(rows: [
            [.red, .green],
            [.blue, .yellow],
        ])
        let stitcher = ScrollingScreenshotStitcher(shiftDetector: { _, _ in 0 })

        _ = stitcher.start(with: image)

        XCTAssertNil(stitcher.append(image))
        XCTAssertEqual(stitcher.currentImage?.height, 2)
    }

    func testAppendingUpwardFrameAddsOnlyNewTopRows() throws {
        let first = makeImage(rows: [
            [.blue, .yellow],
            [.cyan, .magenta],
            [.black, .white],
        ])
        let second = makeImage(rows: [
            [.red, .green],
            [.blue, .yellow],
            [.cyan, .magenta],
        ])
        let stitcher = ScrollingScreenshotStitcher(shiftDetector: { _, _ in 1 })

        _ = stitcher.start(with: first)
        let stitched = try XCTUnwrap(stitcher.append(second))

        XCTAssertEqual(stitched.width, 2)
        XCTAssertEqual(stitched.height, 4)
        XCTAssertEqual((0..<2).map { pixel(atX: $0, y: 0, in: stitched) }, [.red, .green])
        XCTAssertEqual((0..<2).map { pixel(atX: $0, y: 1, in: stitched) }, [.blue, .yellow])
        XCTAssertEqual((0..<2).map { pixel(atX: $0, y: 2, in: stitched) }, [.cyan, .magenta])
        XCTAssertEqual((0..<2).map { pixel(atX: $0, y: 3, in: stitched) }, [.black, .white])
    }

    func testPreferredUpwardDirectionSkipsAlreadyCapturedReversalRows() throws {
        let first = makeImage(rows: [
            [.red, .green],
            [.blue, .yellow],
            [.cyan, .magenta],
        ])
        let reversalFrame = makeImage(rows: [
            [.blue, .yellow],
            [.cyan, .magenta],
            [.black, .white],
        ])
        let stitcher = ScrollingScreenshotStitcher(shiftDetector: { _, _ in -1 })

        _ = stitcher.start(with: first)
        let result = stitcher.appendAnalyzed(
            reversalFrame,
            preferredScrollDirection: .upward
        )

        XCTAssertNil(result.image)
        XCTAssertEqual(result.failureReason, .duplicateFrame)
        XCTAssertEqual(stitcher.currentImage?.height, 3)
    }

    func testScrollingBackToAlreadyCapturedRowsDoesNotGrowImage() throws {
        let first = makeImage(rows: [
            [.red, .green],
            [.blue, .yellow],
            [.cyan, .magenta],
        ])
        let scrolledDown = makeImage(rows: [
            [.blue, .yellow],
            [.cyan, .magenta],
            [.black, .white],
        ])
        let stitcher = ScrollingScreenshotStitcher(shiftDetector: { _, _ in -1 })

        _ = stitcher.start(with: first)
        let stitched = try XCTUnwrap(stitcher.append(scrolledDown))
        XCTAssertEqual(stitched.height, 4)

        let result = stitcher.appendAnalyzed(
            first,
            preferredScrollDirection: .upward
        )

        XCTAssertNil(result.image)
        XCTAssertEqual(result.failureReason, .duplicateFrame)
        XCTAssertEqual(stitcher.currentImage?.height, 4)
        XCTAssertEqual((0..<2).map { pixel(atX: $0, y: 0, in: stitched) }, [.red, .green])
    }

    func testScrollingBackToAlreadyCapturedRowsDoesNotGrowImageWithoutPreferredDirection() throws {
        let first = makeImage(rows: [
            [.red, .green],
            [.blue, .yellow],
            [.cyan, .magenta],
        ])
        let scrolledDown = makeImage(rows: [
            [.blue, .yellow],
            [.cyan, .magenta],
            [.black, .white],
        ])
        let stitcher = ScrollingScreenshotStitcher(shiftDetector: { _, _ in -1 })

        _ = stitcher.start(with: first)
        let stitched = try XCTUnwrap(stitcher.append(scrolledDown))
        XCTAssertEqual(stitched.height, 4)

        let result = stitcher.appendAnalyzed(first)

        XCTAssertNil(result.image)
        XCTAssertEqual(result.failureReason, .duplicateFrame)
        XCTAssertEqual(stitcher.currentImage?.height, 4)
    }

    func testReverseScrollAfterInitialDownwardCaptureDoesNotPrependTopRows() throws {
        let initial = makeImage(rows: [
            [.red, .red],
            [.green, .green],
            [.blue, .blue],
        ])
        let scrolledDown = makeImage(rows: [
            [.green, .green],
            [.blue, .blue],
            [.yellow, .yellow],
        ])
        let reverseScrolledAboveInitial = makeImage(rows: [
            [.black, .black],
            [.red, .red],
            [.green, .green],
        ])
        let stitcher = ScrollingScreenshotStitcher(shiftDetector: { current, _ in
            current.dataProvider?.data == scrolledDown.dataProvider?.data ? -1 : 1
        })

        _ = stitcher.start(with: initial)
        let stitchedDown = try XCTUnwrap(
            stitcher.appendAnalyzed(
                scrolledDown,
                preferredScrollDirection: .downward
            ).image
        )
        XCTAssertEqual(stitchedDown.height, 4)

        let result = stitcher.appendAnalyzed(
            reverseScrolledAboveInitial,
            preferredScrollDirection: .upward
        )

        XCTAssertNil(result.image)
        XCTAssertEqual(result.failureReason, .duplicateFrame)
        XCTAssertEqual(stitcher.currentImage?.height, 4)
        XCTAssertEqual((0..<2).map { pixel(atX: $0, y: 0, in: stitchedDown) }, [.red, .red])
        XCTAssertEqual((0..<2).map { pixel(atX: $0, y: 3, in: stitchedDown) }, [.yellow, .yellow])
    }

    func testReverseRejectedFrameDoesNotBecomeBaselineForResumedForwardScroll() throws {
        let initial = makeImage(rows: [
            [.red, .red],
            [.green, .green],
            [.blue, .blue],
        ])
        let scrolledDown = makeImage(rows: [
            [.green, .green],
            [.blue, .blue],
            [.yellow, .yellow],
        ])
        let reverseFrame = initial
        let resumedDown = makeImage(rows: [
            [.blue, .blue],
            [.yellow, .yellow],
            [.white, .white],
        ])
        var comparedResumedFrameAgainstAcceptedFrame = false
        let stitcher = ScrollingScreenshotStitcher(shiftEstimator: { current, previous in
            if current.dataProvider?.data == scrolledDown.dataProvider?.data,
               previous.dataProvider?.data == initial.dataProvider?.data {
                return ScrollingScreenshotShiftEstimate(rows: -1, agreeingBandCount: 1, totalBandCount: 1)
            }
            if current.dataProvider?.data == reverseFrame.dataProvider?.data,
               previous.dataProvider?.data == scrolledDown.dataProvider?.data {
                return ScrollingScreenshotShiftEstimate(rows: 1, agreeingBandCount: 1, totalBandCount: 1)
            }
            if current.dataProvider?.data == resumedDown.dataProvider?.data,
               previous.dataProvider?.data == scrolledDown.dataProvider?.data {
                comparedResumedFrameAgainstAcceptedFrame = true
                return ScrollingScreenshotShiftEstimate(rows: -1, agreeingBandCount: 1, totalBandCount: 1)
            }
            return nil
        })

        _ = stitcher.start(with: initial)
        let stitchedDown = try XCTUnwrap(
            stitcher.appendAnalyzed(
                scrolledDown,
                preferredScrollDirection: .downward
            ).image
        )
        XCTAssertEqual(stitchedDown.height, 4)

        let reverseResult = stitcher.appendAnalyzed(
            reverseFrame,
            preferredScrollDirection: .upward
        )
        let resumedResult = stitcher.appendAnalyzed(
            resumedDown,
            preferredScrollDirection: .downward
        )

        XCTAssertNil(reverseResult.image)
        XCTAssertEqual(reverseResult.failureReason, .duplicateFrame)
        XCTAssertTrue(comparedResumedFrameAgainstAcceptedFrame)
        XCTAssertEqual(resumedResult.image?.height, 5)
        XCTAssertEqual(stitcher.currentImage?.height, 5)
    }

    func testReverseScrollAfterInitialUpwardCaptureDoesNotAppendBottomRows() throws {
        let initial = makeImage(rows: [
            [.green, .green],
            [.blue, .blue],
            [.yellow, .yellow],
        ])
        let scrolledUp = makeImage(rows: [
            [.red, .red],
            [.green, .green],
            [.blue, .blue],
        ])
        let reverseScrolledPastOriginalBottom = makeImage(rows: [
            [.blue, .blue],
            [.yellow, .yellow],
            [.white, .white],
        ])
        let stitcher = ScrollingScreenshotStitcher(shiftDetector: { current, _ in
            current.dataProvider?.data == scrolledUp.dataProvider?.data ? 1 : -1
        })

        _ = stitcher.start(with: initial)
        let stitchedUp = try XCTUnwrap(
            stitcher.appendAnalyzed(
                scrolledUp,
                preferredScrollDirection: .upward
            ).image
        )
        XCTAssertEqual(stitchedUp.height, 4)

        let result = stitcher.appendAnalyzed(
            reverseScrolledPastOriginalBottom,
            preferredScrollDirection: .downward
        )

        XCTAssertNil(result.image)
        XCTAssertEqual(result.failureReason, .duplicateFrame)
        XCTAssertEqual(stitcher.currentImage?.height, 4)
        XCTAssertEqual((0..<2).map { pixel(atX: $0, y: 0, in: stitchedUp) }, [.red, .red])
        XCTAssertEqual((0..<2).map { pixel(atX: $0, y: 3, in: stitchedUp) }, [.yellow, .yellow])
    }

    func testDefaultShiftDetectorReportsPositiveRowsForDownwardScroll() throws {
        let shift = 8
        let first = makePatternImage(width: 64, height: 96)
        let second = makeScrolledImage(from: first, shift: shift)

        let detectedShift = try XCTUnwrap(
            ScrollingScreenshotStitcher.detectVerticalShift(current: second, previous: first)
        )

        XCTAssertGreaterThan(detectedShift, 0)
        XCTAssertEqual(detectedShift, shift, accuracy: 2)
    }

    func testDefaultShiftDetectorReportsNegativeRowsForUpwardScroll() throws {
        let shift = -8
        let first = makePatternImage(width: 64, height: 96)
        let second = makeScrolledImage(from: first, shift: shift)

        let detectedShift = try XCTUnwrap(
            ScrollingScreenshotStitcher.detectVerticalShift(current: second, previous: first)
        )

        XCTAssertLessThan(detectedShift, 0)
        XCTAssertEqual(detectedShift, shift, accuracy: 2)
    }

    func testBandVotedShiftDetectorReturnsMajorityOffset() throws {
        let first = makePatternImage(width: 80, height: 150)
        let second = makeScrolledImage(from: first, shift: 12)

        let estimate = try XCTUnwrap(
            ScrollingScreenshotStitcher.detectVerticalShiftEstimate(
                current: second,
                previous: first,
                configuration: .init(bandCount: 5, agreementRatio: 0.75, toleranceRows: 3, minimumShiftRows: 3)
            )
        )

        XCTAssertLessThanOrEqual(abs(estimate.rows - 12), 3)
        XCTAssertGreaterThanOrEqual(estimate.agreeingBandCount, 4)
        XCTAssertEqual(estimate.totalBandCount, 5)
    }

    func testBandVotedShiftDetectorRejectsDisagreement() {
        let first = makePatternImage(width: 80, height: 150)
        let second = makePatternImage(width: 80, height: 150)
        let estimate = ScrollingScreenshotStitcher.detectVerticalShiftEstimate(
            current: second,
            previous: first,
            configuration: .init(bandCount: 5, agreementRatio: 0.75, toleranceRows: 1, minimumShiftRows: 3),
            bandShiftDetector: { band, _, _ in
                switch band {
                case 0: return 10
                case 1: return -8
                case 2: return 3
                case 3: return 21
                default: return nil
                }
            }
        )

        XCTAssertNil(estimate)
    }

    func testBandVotedShiftDetectorFallsBackToWholeFrameOffsetWhenBandsDisagree() throws {
        let first = makePatternImage(width: 80, height: 150)
        let second = makePatternImage(width: 80, height: 150)
        let estimate = try XCTUnwrap(
            ScrollingScreenshotStitcher.detectVerticalShiftEstimate(
                current: second,
                previous: first,
                configuration: .init(bandCount: 5, agreementRatio: 0.75, toleranceRows: 1, minimumShiftRows: 3),
                bandShiftDetector: { band, _, _ in
                    switch band {
                    case 0: return 10
                    case 1: return -8
                    case 2: return 3
                    case 3: return 21
                    default: return nil
                    }
                },
                fallbackShiftDetector: { _, _ in 12 }
            )
        )

        XCTAssertEqual(estimate.rows, 12)
        XCTAssertEqual(estimate.agreeingBandCount, 1)
        XCTAssertEqual(estimate.totalBandCount, 1)
    }

    func testAppendReturnsSkippedWhenBandVoteDisagrees() {
        let first = makePatternImage(width: 80, height: 150)
        let second = makeImage(width: 80, height: 150) { x, y in
            RGBA(
                red: UInt8((x * 19 + y * 7) % 255),
                green: UInt8((x * 3 + y * 17) % 255),
                blue: UInt8((x * 11 + y * 23) % 255),
                alpha: 255
            )
        }
        let stitcher = ScrollingScreenshotStitcher(
            shiftEstimator: { _, _ in nil }
        )

        _ = stitcher.start(with: first)
        let result = stitcher.appendAnalyzed(second)

        XCTAssertNil(result.image)
        XCTAssertEqual(result.failureReason, .bandVoteDisagreed)
    }

    func testAppendClassifiesZeroShiftAsNoMovement() {
        let first = makePatternImage(width: 80, height: 150)
        let second = makeImage(width: 80, height: 150) { x, y in
            RGBA(
                red: UInt8((x * 19 + y * 7) % 255),
                green: UInt8((x * 3 + y * 17) % 255),
                blue: UInt8((x * 11 + y * 23) % 255),
                alpha: 255
            )
        }
        let stitcher = ScrollingScreenshotStitcher(
            shiftEstimator: { _, _ in
                ScrollingScreenshotShiftEstimate(rows: 0, agreeingBandCount: 5, totalBandCount: 5)
            }
        )

        _ = stitcher.start(with: first)
        let result = stitcher.appendAnalyzed(second)

        XCTAssertNil(result.image)
        XCTAssertEqual(result.failureReason, .shiftTooSmall(0))
    }

    func testTinyShiftDoesNotAdvancePreviousFrameUntilOffsetAccumulates() throws {
        let first = makePatternImage(width: 2, height: 20)
        let tinyShift = makeImage(width: 2, height: 20) { x, y in
            RGBA(
                red: UInt8((x * 31 + y * 7 + 5) % 255),
                green: UInt8((x * 13 + y * 11 + 5) % 255),
                blue: UInt8((x * 17 + y * 19 + 5) % 255),
                alpha: 255
            )
        }
        let accumulatedShift = makeImage(width: 2, height: 20) { x, y in
            RGBA(
                red: UInt8((x * 31 + y * 7 + 11) % 255),
                green: UInt8((x * 13 + y * 11 + 11) % 255),
                blue: UInt8((x * 17 + y * 19 + 11) % 255),
                alpha: 255
            )
        }
        var comparedAccumulatedShiftAgainstFirst = false
        let stitcher = ScrollingScreenshotStitcher(shiftEstimator: { current, previous in
            if current.dataProvider?.data == tinyShift.dataProvider?.data {
                return ScrollingScreenshotShiftEstimate(rows: 1, agreeingBandCount: 1, totalBandCount: 1)
            }
            if current.dataProvider?.data == accumulatedShift.dataProvider?.data,
               previous.dataProvider?.data == first.dataProvider?.data {
                comparedAccumulatedShiftAgainstFirst = true
                return ScrollingScreenshotShiftEstimate(rows: 2, agreeingBandCount: 1, totalBandCount: 1)
            }
            return ScrollingScreenshotShiftEstimate(rows: 1, agreeingBandCount: 1, totalBandCount: 1)
        })

        _ = stitcher.start(with: first)
        let tinyResult = stitcher.appendAnalyzed(tinyShift, preferredScrollDirection: .downward)
        let accumulatedResult = stitcher.appendAnalyzed(accumulatedShift, preferredScrollDirection: .downward)

        XCTAssertNil(tinyResult.image)
        XCTAssertEqual(tinyResult.failureReason, .shiftTooSmall(1))
        XCTAssertTrue(comparedAccumulatedShiftAgainstFirst)
        XCTAssertEqual(accumulatedResult.image?.height, 21)
    }

    func testSuccessfulStitchKeepsOneRowOverlapAtBoundary() throws {
        let first = makeImage(rows: [
            [.red, .red],
            [.green, .green],
            [.blue, .blue],
        ])
        let second = makeImage(rows: [
            [.blue, .blue],
            [.yellow, .yellow],
            [.white, .white],
        ])
        let stitcher = ScrollingScreenshotStitcher(shiftDetector: { _, _ in 2 })

        _ = stitcher.start(with: first)
        let result = stitcher.appendAnalyzed(second, preferredScrollDirection: .downward)
        let stitched = try XCTUnwrap(result.image)

        XCTAssertEqual(stitched.height, 4)
        XCTAssertEqual((0..<2).map { pixel(atX: $0, y: 3, in: stitched) }, [.white, .white])
    }

    func testDetectStickyHeaderRowsFindsStableTopRegion() {
        let previous = makeImage(rows: [
            [.red, .red],
            [.red, .red],
            [.blue, .blue],
            [.cyan, .cyan],
        ])
        let current = makeImage(rows: [
            [.red, .red],
            [.red, .red],
            [.cyan, .cyan],
            [.magenta, .magenta],
        ])

        let rows = ScrollingScreenshotStitcher.detectStickyTopRows(
            current: current,
            previous: previous,
            maxHeaderRatio: 0.6,
            minStableRows: 1
        )

        XCTAssertEqual(rows, 2)
    }

    func testDetectStickyHeaderRowsUsesConservativeDefaultLimit() {
        let previous = makeImage(width: 12, height: 100) { x, y in
            y < 60 ? .white : RGBA(
                red: UInt8((x * 11 + y * 3) % 255),
                green: UInt8((x * 5 + y * 7) % 255),
                blue: UInt8((x * 13 + y * 17) % 255),
                alpha: 255
            )
        }
        let current = makeImage(width: 12, height: 100) { x, y in
            y < 60 ? .white : RGBA(
                red: UInt8((x * 19 + y * 23) % 255),
                green: UInt8((x * 29 + y * 31) % 255),
                blue: UInt8((x * 37 + y * 41) % 255),
                alpha: 255
            )
        }

        let rows = ScrollingScreenshotStitcher.detectStickyTopRows(
            current: current,
            previous: previous
        )

        XCTAssertLessThanOrEqual(rows, 20)
    }

    func testDetectRightMarginColumnsFindsChangingScrollbarRegion() {
        let previous = makePatternImage(width: 20, height: 40)
        let current = makeImage(width: 20, height: 40) { x, y in
            if x >= 17 {
                return y.isMultiple(of: 2) ? .black : .white
            }
            return pixel(atX: x, y: y, in: previous)
        }

        let margin = ScrollingScreenshotStitcher.detectRightMarginColumns(
            current: current,
            previous: previous,
            maxScanColumns: 6
        )

        XCTAssertGreaterThanOrEqual(margin, 3)
    }

    private func makeImage(rows: [[RGBA]]) -> CGImage {
        let width = rows[0].count
        let height = rows.count
        let data = Data(rows.flatMap { $0.flatMap(\.bytes) })
        return makeImage(width: width, height: height, data: data)
    }

    private func makePatternImage(width: Int, height: Int) -> CGImage {
        makeImage(width: width, height: height) { x, y in
            RGBA(
                red: UInt8((x * 17 + y * 3) % 255),
                green: UInt8((x * 5 + y * 11) % 255),
                blue: UInt8((x * 13 + y * 7) % 255),
                alpha: 255
            )
        }
    }

    private func makeScrolledImage(from image: CGImage, shift: Int) -> CGImage {
        let sourceData = image.dataProvider!.data! as Data
        let width = image.width
        let height = image.height
        let bytesPerRow = image.bytesPerRow
        var output = Data(count: sourceData.count)
        output.withUnsafeMutableBytes { outputBytes in
            sourceData.withUnsafeBytes { sourceBytes in
                guard let outputBase = outputBytes.baseAddress,
                      let sourceBase = sourceBytes.baseAddress else {
                    return
                }
                for y in 0..<height {
                    let outputOffset = y * bytesPerRow
                    let sourceY = y + shift
                    if sourceY >= 0, sourceY < height {
                        memcpy(
                            outputBase.advanced(by: outputOffset),
                            sourceBase.advanced(by: sourceY * bytesPerRow),
                            bytesPerRow
                        )
                    } else {
                        for x in 0..<width {
                            let pixel = RGBA(
                                red: UInt8((x * 17 + abs(sourceY) * 3) % 255),
                                green: UInt8((x * 5 + abs(sourceY) * 11) % 255),
                                blue: UInt8((x * 13 + abs(sourceY) * 7) % 255),
                                alpha: 255
                            )
                            let offset = outputOffset + x * 4
                            let bytes = pixel.bytes
                            memcpy(outputBase.advanced(by: offset), bytes, 4)
                        }
                    }
                }
            }
        }
        return makeImage(width: width, height: height, data: output)
    }

    private func makeImage(
        width: Int,
        height: Int,
        pixel: (_ x: Int, _ y: Int) -> RGBA
    ) -> CGImage {
        var data = Data()
        data.reserveCapacity(width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                data.append(contentsOf: pixel(x, y).bytes)
            }
        }
        return makeImage(width: width, height: height, data: data)
    }

    private func makeImage(width: Int, height: Int, data: Data) -> CGImage {
        let provider = CGDataProvider(data: data as CFData)!
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }

    private func pixel(atX x: Int, y: Int, in image: CGImage) -> RGBA {
        let data = image.dataProvider!.data! as Data
        let offset = y * image.bytesPerRow + x * 4
        return RGBA(
            red: data[offset],
            green: data[offset + 1],
            blue: data[offset + 2],
            alpha: data[offset + 3]
        )
    }
}

private struct RGBA: Equatable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8
    let alpha: UInt8

    var bytes: [UInt8] { [red, green, blue, alpha] }

    static let red = RGBA(red: 255, green: 0, blue: 0, alpha: 255)
    static let green = RGBA(red: 0, green: 255, blue: 0, alpha: 255)
    static let blue = RGBA(red: 0, green: 0, blue: 255, alpha: 255)
    static let yellow = RGBA(red: 255, green: 255, blue: 0, alpha: 255)
    static let cyan = RGBA(red: 0, green: 255, blue: 255, alpha: 255)
    static let magenta = RGBA(red: 255, green: 0, blue: 255, alpha: 255)
    static let black = RGBA(red: 0, green: 0, blue: 0, alpha: 255)
    static let white = RGBA(red: 255, green: 255, blue: 255, alpha: 255)
}
