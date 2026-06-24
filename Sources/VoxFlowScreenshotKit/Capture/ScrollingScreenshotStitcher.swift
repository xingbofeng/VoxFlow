import CoreGraphics
import Foundation
import Vision

// GPLv3-scoped behavior attribution:
// The scrolling screenshot stitching model is adapted from sw33tLie/macshot.
// Source: https://github.com/sw33tLie/macshot
// Upstream commit: b8ebcb454f957fda011821fbf9c104580592d135
// License: GPLv3

public enum ScrollingScreenshotScrollDirection: Equatable, Sendable {
    case upward
    case downward
}

public struct ScrollingScreenshotShiftDetectionConfiguration: Equatable, Sendable {
    public let bandCount: Int
    public let agreementRatio: Double
    public let toleranceRows: Int
    public let minimumShiftRows: Int

    public init(
        bandCount: Int = 5,
        agreementRatio: Double = 0.75,
        toleranceRows: Int = 3,
        minimumShiftRows: Int = 3
    ) {
        self.bandCount = max(1, bandCount)
        self.agreementRatio = min(max(agreementRatio, 0), 1)
        self.toleranceRows = max(0, toleranceRows)
        self.minimumShiftRows = max(0, minimumShiftRows)
    }
}

public final class ScrollingScreenshotStitcher: @unchecked Sendable {
    public typealias ShiftDetector = (_ current: CGImage, _ previous: CGImage) -> Int?
    public typealias ShiftEstimator = (_ current: CGImage, _ previous: CGImage) -> ScrollingScreenshotShiftEstimate?

    private let shiftEstimator: ShiftEstimator?
    private(set) public var currentImage: CGImage?
    private(set) var lastScrollDirection: ScrollingScreenshotScrollDirection?
    private var captureDirection: ScrollingScreenshotScrollDirection?
    private var previousFrame: CGImage?
    private var stickyTopRows = 0
    private var rightMarginColumns = 0
    private var hasDetectedExclusions = false
    private var stitchedRowHashes: [UInt64] = []

    public init() {
        shiftEstimator = nil
    }

    public convenience init(shiftDetector: @escaping ShiftDetector) {
        self.init { current, previous in
            guard let rows = shiftDetector(current, previous), rows != 0 else { return nil }
            return ScrollingScreenshotShiftEstimate(
                rows: rows,
                agreeingBandCount: 1,
                totalBandCount: 1
            )
        }
    }

    public init(shiftEstimator: @escaping ShiftEstimator) {
        self.shiftEstimator = shiftEstimator
    }

    @discardableResult
    public func start(with image: CGImage) -> CGImage {
        currentImage = image
        previousFrame = image
        lastScrollDirection = nil
        captureDirection = nil
        stickyTopRows = 0
        rightMarginColumns = 0
        hasDetectedExclusions = false
        stitchedRowHashes = Self.rowHashes(in: image)
        return image
    }

    @discardableResult
    public func append(_ image: CGImage) -> CGImage? {
        appendAnalyzed(image).image
    }

    @discardableResult
    public func appendAnalyzed(
        _ image: CGImage,
        maxPixelHeight: Int? = nil,
        preferredScrollDirection: ScrollingScreenshotScrollDirection? = nil
    ) -> ScrollingScreenshotStitchResult {
        guard let previousFrame,
              let currentImage,
              image.width == previousFrame.width,
              image.height == previousFrame.height,
              image.width == currentImage.width else {
            return .skipped(.frameSizeChanged)
        }

        guard image.dataProvider?.data != previousFrame.dataProvider?.data else {
            return .skipped(.duplicateFrame)
        }

        if !hasDetectedExclusions {
            stickyTopRows = Self.detectStickyTopRows(current: image, previous: previousFrame)
            rightMarginColumns = Self.detectRightMarginColumns(current: image, previous: previousFrame)
            hasDetectedExclusions = true
            stitchedRowHashes = Self.rowHashes(in: currentImage, excludedRightColumns: rightMarginColumns)
            ScrollingScreenshotDiagnostics.logger.info(
                "scrolling_stitch_exclusions stickyTopRows=\(self.stickyTopRows, privacy: .public) rightMarginColumns=\(self.rightMarginColumns, privacy: .public) frame=\(ScrollingScreenshotDiagnostics.size(image), privacy: .public)"
            )
        }

        guard let estimate = estimateShift(current: image, previous: previousFrame) else {
            return .skipped(.bandVoteDisagreed)
        }
        guard estimate.rows != 0 else {
            return .skipped(.shiftTooSmall(0))
        }

        let shift = estimate.rows
        let detectedRows = min(abs(shift), image.height)
        let minimumStitchRows = max(1, image.height / 10)
        guard detectedRows >= minimumStitchRows else {
            ScrollingScreenshotDiagnostics.logger.info(
                "scrolling_append_skip_tiny_shift rows=\(detectedRows, privacy: .public) min=\(minimumStitchRows, privacy: .public)"
            )
            return .skipped(.shiftTooSmall(shift))
        }

        let safeDetectedRows = max(1, detectedRows - 1)
        let remainingRows = maxPixelHeight.map { max(0, $0 - currentImage.height) } ?? safeDetectedRows
        let newRows = min(safeDetectedRows, remainingRows)
        guard newRows > 0 else {
            return .skipped(.shiftTooSmall(shift))
        }

        let scrollDirection = preferredScrollDirection ?? Self.resolveScrollDirection(
            current: image,
            previous: previousFrame,
            shiftedRows: detectedRows,
            excludedTopRows: stickyTopRows,
            excludedRightColumns: rightMarginColumns
        ) ?? (shift > 0 ? .downward : .upward)
        if let captureDirection, scrollDirection != captureDirection {
            ScrollingScreenshotDiagnostics.logger.info(
                "scrolling_append_skip_reverse locked=\(String(describing: captureDirection), privacy: .public) detected=\(String(describing: scrollDirection), privacy: .public) rows=\(newRows, privacy: .public)"
            )
            return .skipped(.duplicateFrame)
        }
        let newRowRange = scrollDirection == .downward
            ? (image.height - newRows)..<image.height
            : 0..<newRows
        let newRowHashes = Self.rowHashes(
            in: image,
            rows: newRowRange,
            excludedRightColumns: rightMarginColumns
        )
        if Self.containsContiguousSequence(newRowHashes, in: stitchedRowHashes) {
            ScrollingScreenshotDiagnostics.logger.info(
                "scrolling_append_skip_already_captured direction=\(String(describing: scrollDirection), privacy: .public) rows=\(newRows, privacy: .public)"
            )
            self.previousFrame = image
            return .skipped(.duplicateFrame)
        }
        let duplicateBoundaryRows = switch scrollDirection {
        case .downward:
            Self.longestPrefixSuffixOverlap(prefix: newRowHashes, suffix: stitchedRowHashes)
        case .upward:
            Self.longestSuffixPrefixOverlap(suffix: newRowHashes, prefix: stitchedRowHashes)
        }
        let rowsToWrite = newRows - duplicateBoundaryRows
        guard rowsToWrite > 0 else {
            self.previousFrame = image
            return .skipped(.duplicateFrame)
        }
        let rowHashesToWrite = scrollDirection == .downward
            ? Array(newRowHashes.suffix(rowsToWrite))
            : Array(newRowHashes.prefix(rowsToWrite))

        let stitched = scrollDirection == .downward
            ? Self.appendBottomRows(from: image, rowCount: rowsToWrite, to: currentImage)
            : Self.prependTopRows(from: image, rowCount: rowsToWrite, to: currentImage)
        guard let stitched else {
            return .skipped(.shiftNotDetected)
        }
        self.currentImage = stitched
        self.previousFrame = image
        self.lastScrollDirection = scrollDirection
        if captureDirection == nil {
            captureDirection = scrollDirection
        }
        if rowHashesToWrite.isEmpty {
            stitchedRowHashes = Self.rowHashes(in: stitched, excludedRightColumns: rightMarginColumns)
        } else if scrollDirection == .downward {
            stitchedRowHashes.append(contentsOf: rowHashesToWrite)
        } else {
            stitchedRowHashes.insert(contentsOf: rowHashesToWrite, at: 0)
        }
        return .stitched(stitched, estimate: estimate)
    }

    private func estimateShift(current: CGImage, previous: CGImage) -> ScrollingScreenshotShiftEstimate? {
        if let shiftEstimator {
            return shiftEstimator(current, previous)
        }
        return Self.detectVerticalShiftEstimate(
            current: current,
            previous: previous,
            excludedTopRows: stickyTopRows,
            excludedRightColumns: rightMarginColumns,
            fallbackShiftDetector: Self.detectVerticalShift
        )
    }

    public static func detectVerticalShift(current: CGImage, previous: CGImage) -> Int? {
        guard current.width == previous.width,
              current.height == previous.height else {
            return nil
        }

        let request = VNTranslationalImageRegistrationRequest(targetedCGImage: previous)
        let handler = VNImageRequestHandler(cgImage: current, options: [:])
        guard (try? handler.perform([request])) != nil,
              let observation = request.results?.first as? VNImageTranslationAlignmentObservation else {
            return nil
        }

        return Int(round(observation.alignmentTransform.ty))
    }

    public static func detectVerticalShiftEstimate(
        current: CGImage,
        previous: CGImage,
        configuration: ScrollingScreenshotShiftDetectionConfiguration = .init(),
        excludedTopRows: Int = 0,
        excludedRightColumns: Int = 0,
        bandShiftDetector: ((_ bandIndex: Int, _ currentBand: CGImage, _ previousBand: CGImage) -> Int?)? = nil,
        fallbackShiftDetector: ((_ current: CGImage, _ previous: CGImage) -> Int?)? = nil
    ) -> ScrollingScreenshotShiftEstimate? {
        guard current.width == previous.width,
              current.height == previous.height else {
            return nil
        }

        func fallbackEstimate() -> ScrollingScreenshotShiftEstimate? {
            guard let rows = fallbackShiftDetector?(current, previous) else {
                ScrollingScreenshotDiagnostics.logger.info(
                    "scrolling_shift_fallback rows=nil min=\(configuration.minimumShiftRows, privacy: .public)"
                )
                return nil
            }
            guard abs(rows) >= configuration.minimumShiftRows else {
                ScrollingScreenshotDiagnostics.logger.info(
                    "scrolling_shift_fallback rows=\(rows, privacy: .public) rejected=minShift min=\(configuration.minimumShiftRows, privacy: .public)"
                )
                return nil
            }
            ScrollingScreenshotDiagnostics.logger.info(
                "scrolling_shift_fallback rows=\(rows, privacy: .public) accepted min=\(configuration.minimumShiftRows, privacy: .public)"
            )
            return ScrollingScreenshotShiftEstimate(
                rows: rows,
                agreeingBandCount: 1,
                totalBandCount: 1,
                excludedTopRows: excludedTopRows,
                excludedRightColumns: excludedRightColumns
            )
        }

        let cropTop = min(max(0, excludedTopRows), current.height - 1)
        let cropRight = min(max(0, excludedRightColumns), current.width - 1)
        let cropWidth = current.width - cropRight
        let cropHeight = current.height - cropTop
        guard cropWidth > 20, cropHeight > 20 else { return fallbackEstimate() }

        let bandCount = min(configuration.bandCount, max(1, cropHeight / 20))
        let bandHeight = max(20, cropHeight / bandCount)
        var offsets: [Int] = []
        var totalBands = 0

        for bandIndex in 0..<bandCount {
            let maxOriginY = max(0, cropHeight - bandHeight)
            let denominator = max(1, bandCount - 1)
            let originY = cropTop + min(
                maxOriginY,
                Int((Double(maxOriginY) * Double(bandIndex) / Double(denominator)).rounded())
            )
            let rect = CGRect(x: 0, y: originY, width: cropWidth, height: bandHeight)
            guard let currentBand = current.cropping(to: rect),
                  let previousBand = previous.cropping(to: rect) else {
                continue
            }
            totalBands += 1
            let offset = bandShiftDetector?(bandIndex, currentBand, previousBand)
                ?? detectVerticalShift(current: currentBand, previous: previousBand)
            if let offset, abs(offset) >= configuration.minimumShiftRows {
                offsets.append(offset)
            }
        }

        guard totalBands > 0, offsets.first != nil else {
            ScrollingScreenshotDiagnostics.logger.info(
                "scrolling_shift_bands_empty total=\(totalBands, privacy: .public) offsets=\(String(describing: offsets), privacy: .public)"
            )
            return fallbackEstimate()
        }
        var bestGroup: [Int] = []
        for offset in offsets {
            let group = offsets.filter { abs($0 - offset) <= configuration.toleranceRows }
            if group.count > bestGroup.count {
                bestGroup = group
            }
        }

        let requiredAgreement = max(1, Int(ceil(Double(totalBands) * configuration.agreementRatio)))
        guard bestGroup.count >= requiredAgreement else {
            ScrollingScreenshotDiagnostics.logger.info(
                "scrolling_shift_bands_disagree total=\(totalBands, privacy: .public) required=\(requiredAgreement, privacy: .public) offsets=\(String(describing: offsets), privacy: .public) best=\(String(describing: bestGroup), privacy: .public)"
            )
            return fallbackEstimate()
        }

        let average = Double(bestGroup.reduce(0, +)) / Double(bestGroup.count)
        let rows = Int(round(average))
        guard abs(rows) >= configuration.minimumShiftRows else {
            ScrollingScreenshotDiagnostics.logger.info(
                "scrolling_shift_bands_small rows=\(rows, privacy: .public) total=\(totalBands, privacy: .public) offsets=\(String(describing: offsets), privacy: .public) best=\(String(describing: bestGroup), privacy: .public)"
            )
            return fallbackEstimate()
        }

        ScrollingScreenshotDiagnostics.logger.info(
            "scrolling_shift_bands_ok rows=\(rows, privacy: .public) total=\(totalBands, privacy: .public) required=\(requiredAgreement, privacy: .public) offsets=\(String(describing: offsets), privacy: .public) best=\(String(describing: bestGroup), privacy: .public)"
        )

        return ScrollingScreenshotShiftEstimate(
            rows: rows,
            agreeingBandCount: bestGroup.count,
            totalBandCount: totalBands,
            excludedTopRows: excludedTopRows,
            excludedRightColumns: excludedRightColumns
        )
    }

    public static func detectStickyTopRows(
        current: CGImage,
        previous: CGImage,
        maxHeaderRatio: Double = 0.2,
        minStableRows: Int = 10
    ) -> Int {
        guard current.width == previous.width,
              current.height == previous.height,
              let currentData = rgbaData(for: current),
              let previousData = rgbaData(for: previous) else {
            return 0
        }

        let width = current.width
        let height = current.height
        let maxRows = Int(Double(height) * min(maxHeaderRatio, 1))
        let rowLength = width * 4
        var stickyRows = 0

        for row in 0..<maxRows {
            let offset = row * rowLength
            let end = offset + rowLength
            guard end <= currentData.count, end <= previousData.count else { break }
            if currentData[offset..<end] == previousData[offset..<end] {
                stickyRows += 1
            } else {
                break
            }
        }

        return stickyRows >= minStableRows ? stickyRows : 0
    }

    private static func resolveScrollDirection(
        current: CGImage,
        previous: CGImage,
        shiftedRows: Int,
        excludedTopRows: Int,
        excludedRightColumns: Int
    ) -> ScrollingScreenshotScrollDirection? {
        guard shiftedRows > 0,
              shiftedRows < current.height,
              current.width == previous.width,
              current.height == previous.height,
              let currentData = rgbaData(for: current),
              let previousData = rgbaData(for: previous) else {
            return nil
        }

        let width = current.width
        let height = current.height
        let compareWidth = width - min(max(0, excludedRightColumns), max(0, width - 1))
        let topRows = min(max(0, excludedTopRows), max(0, height - shiftedRows - 1))
        let overlapRows = height - shiftedRows - topRows
        guard compareWidth > 0, overlapRows > 0 else { return nil }

        let downwardScore = overlapDifference(
            currentData: currentData,
            previousData: previousData,
            width: width,
            compareWidth: compareWidth,
            currentStartY: topRows,
            previousStartY: topRows + shiftedRows,
            rows: overlapRows
        )
        let upwardScore = overlapDifference(
            currentData: currentData,
            previousData: previousData,
            width: width,
            compareWidth: compareWidth,
            currentStartY: topRows + shiftedRows,
            previousStartY: topRows,
            rows: overlapRows
        )

        guard let downwardScore, let upwardScore else { return nil }
        ScrollingScreenshotDiagnostics.logger.debug(
            "scrolling_direction_score shift=\(shiftedRows, privacy: .public) down=\(downwardScore, privacy: .public) up=\(upwardScore, privacy: .public)"
        )
        return downwardScore <= upwardScore ? .downward : .upward
    }

    private static func overlapDifference(
        currentData: Data,
        previousData: Data,
        width: Int,
        compareWidth: Int,
        currentStartY: Int,
        previousStartY: Int,
        rows: Int
    ) -> Double? {
        let bytesPerPixel = 4
        let rowLength = width * bytesPerPixel
        let rowStep = max(1, rows / 80)
        let columnStep = max(1, compareWidth / 120)
        var totalDifference: UInt64 = 0
        var sampleCount: UInt64 = 0

        for rowOffset in stride(from: 0, to: rows, by: rowStep) {
            let currentY = currentStartY + rowOffset
            let previousY = previousStartY + rowOffset
            let currentRowOffset = currentY * rowLength
            let previousRowOffset = previousY * rowLength
            guard currentRowOffset + compareWidth * bytesPerPixel <= currentData.count,
                  previousRowOffset + compareWidth * bytesPerPixel <= previousData.count else {
                continue
            }

            for x in stride(from: 0, to: compareWidth, by: columnStep) {
                let currentOffset = currentRowOffset + x * bytesPerPixel
                let previousOffset = previousRowOffset + x * bytesPerPixel
                totalDifference += UInt64(abs(Int(currentData[currentOffset]) - Int(previousData[previousOffset])))
                totalDifference += UInt64(abs(Int(currentData[currentOffset + 1]) - Int(previousData[previousOffset + 1])))
                totalDifference += UInt64(abs(Int(currentData[currentOffset + 2]) - Int(previousData[previousOffset + 2])))
                sampleCount += 3
            }
        }

        guard sampleCount > 0 else { return nil }
        return Double(totalDifference) / Double(sampleCount)
    }

    private static func longestPrefixSuffixOverlap(
        prefix candidate: [UInt64],
        suffix existing: [UInt64]
    ) -> Int {
        guard !candidate.isEmpty, !existing.isEmpty else { return 0 }
        let maxCount = min(candidate.count, existing.count)
        for count in stride(from: maxCount, through: 1, by: -1) {
            if Array(candidate.prefix(count)) == Array(existing.suffix(count)) {
                return count
            }
        }
        return 0
    }

    private static func longestSuffixPrefixOverlap(
        suffix candidate: [UInt64],
        prefix existing: [UInt64]
    ) -> Int {
        guard !candidate.isEmpty, !existing.isEmpty else { return 0 }
        let maxCount = min(candidate.count, existing.count)
        for count in stride(from: maxCount, through: 1, by: -1) {
            if Array(candidate.suffix(count)) == Array(existing.prefix(count)) {
                return count
            }
        }
        return 0
    }

    public static func detectRightMarginColumns(
        current: CGImage,
        previous: CGImage,
        maxScanColumns: Int = 50
    ) -> Int {
        guard current.width == previous.width,
              current.height == previous.height,
              let currentData = rgbaData(for: current),
              let previousData = rgbaData(for: previous) else {
            return 0
        }

        let width = current.width
        let height = current.height
        let rowLength = width * 4
        let scanColumns = min(maxScanColumns, max(1, width / 4))
        var changingColumns = 0

        for offsetFromRight in 0..<scanColumns {
            let x = width - 1 - offsetFromRight
            var diffCount = 0
            for y in stride(from: height / 5, to: height * 4 / 5, by: max(1, height / 40)) {
                let offset = y * rowLength + x * 4
                guard offset + 2 < currentData.count, offset + 2 < previousData.count else { continue }
                let delta =
                    abs(Int(currentData[offset]) - Int(previousData[offset])) +
                    abs(Int(currentData[offset + 1]) - Int(previousData[offset + 1])) +
                    abs(Int(currentData[offset + 2]) - Int(previousData[offset + 2]))
                if delta > 8 {
                    diffCount += 1
                }
            }
            if diffCount > 0 {
                changingColumns = offsetFromRight + 1
            } else if changingColumns > 0 {
                break
            }
        }

        return changingColumns >= 3 ? min(changingColumns + 4, scanColumns) : 0
    }

    private static func appendBottomRows(
        from image: CGImage,
        rowCount: Int,
        to baseImage: CGImage
    ) -> CGImage? {
        guard rowCount > 0,
              rowCount <= image.height,
              let baseData = rgbaData(for: baseImage),
              let imageData = rgbaData(for: image) else {
            return nil
        }

        let width = baseImage.width
        let bytesPerPixel = 4
        let outputHeight = baseImage.height + rowCount
        var output = Data(count: width * outputHeight * bytesPerPixel)

        output.withUnsafeMutableBytes { outputBytes in
            guard let outputBase = outputBytes.baseAddress else { return }
            baseData.withUnsafeBytes { baseBytes in
                guard let baseAddress = baseBytes.baseAddress else { return }
                memcpy(outputBase, baseAddress, baseData.count)
            }
            imageData.withUnsafeBytes { imageBytes in
                guard let imageAddress = imageBytes.baseAddress else { return }
                let sourceOffset = (image.height - rowCount) * width * bytesPerPixel
                let destinationOffset = baseData.count
                memcpy(
                    outputBase.advanced(by: destinationOffset),
                    imageAddress.advanced(by: sourceOffset),
                    rowCount * width * bytesPerPixel
                )
            }
        }

        let provider = CGDataProvider(data: output as CFData)
        return provider.flatMap {
            CGImage(
                width: width,
                height: outputHeight,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * bytesPerPixel,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: $0,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        }
    }

    private static func prependTopRows(
        from image: CGImage,
        rowCount: Int,
        to baseImage: CGImage
    ) -> CGImage? {
        guard rowCount > 0,
              rowCount <= image.height,
              let baseData = rgbaData(for: baseImage),
              let imageData = rgbaData(for: image) else {
            return nil
        }

        let width = baseImage.width
        let bytesPerPixel = 4
        let outputHeight = baseImage.height + rowCount
        var output = Data(count: width * outputHeight * bytesPerPixel)

        output.withUnsafeMutableBytes { outputBytes in
            guard let outputBase = outputBytes.baseAddress else { return }
            imageData.withUnsafeBytes { imageBytes in
                guard let imageAddress = imageBytes.baseAddress else { return }
                memcpy(
                    outputBase,
                    imageAddress,
                    rowCount * width * bytesPerPixel
                )
            }
            baseData.withUnsafeBytes { baseBytes in
                guard let baseAddress = baseBytes.baseAddress else { return }
                let destinationOffset = rowCount * width * bytesPerPixel
                memcpy(
                    outputBase.advanced(by: destinationOffset),
                    baseAddress,
                    baseData.count
                )
            }
        }

        let provider = CGDataProvider(data: output as CFData)
        return provider.flatMap {
            CGImage(
                width: width,
                height: outputHeight,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * bytesPerPixel,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: $0,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        }
    }

    private static func rgbaData(for image: CGImage) -> Data? {
        guard let data = image.dataProvider?.data as Data? else {
            return nil
        }

        let bytesPerPixel = 4
        let rowLength = image.width * bytesPerPixel
        guard image.bitsPerPixel == 32,
              image.bytesPerRow >= rowLength,
              data.count >= image.bytesPerRow * image.height else {
            return nil
        }

        if image.bytesPerRow == rowLength {
            return data
        }

        var compact = Data(count: rowLength * image.height)
        compact.withUnsafeMutableBytes { compactBytes in
            data.withUnsafeBytes { sourceBytes in
                guard let compactBase = compactBytes.baseAddress,
                      let sourceBase = sourceBytes.baseAddress else {
                    return
                }
                for row in 0..<image.height {
                    memcpy(
                        compactBase.advanced(by: row * rowLength),
                        sourceBase.advanced(by: row * image.bytesPerRow),
                        rowLength
                    )
                }
            }
        }
        return compact
    }

    private static func rowHashes(
        in image: CGImage,
        rows requestedRows: Range<Int>? = nil,
        excludedRightColumns: Int = 0
    ) -> [UInt64] {
        guard let data = rgbaData(for: image) else { return [] }
        let bytesPerPixel = 4
        let width = image.width
        let height = image.height
        let excludedColumns = min(max(0, excludedRightColumns), max(0, width - 1))
        let compareWidth = width - excludedColumns
        guard compareWidth > 0 else { return [] }

        let rows = requestedRows ?? 0..<height
        let lowerBound = min(max(0, rows.lowerBound), height)
        let upperBound = min(max(lowerBound, rows.upperBound), height)
        guard lowerBound < upperBound else { return [] }

        let rowLength = width * bytesPerPixel
        let compareBytes = compareWidth * bytesPerPixel
        var hashes: [UInt64] = []
        hashes.reserveCapacity(upperBound - lowerBound)

        data.withUnsafeBytes { bytes in
            guard let base = bytes.bindMemory(to: UInt8.self).baseAddress else { return }
            for row in lowerBound..<upperBound {
                var hash: UInt64 = 14_695_981_039_346_656_037
                let rowBase = base.advanced(by: row * rowLength)
                for offset in 0..<compareBytes {
                    hash ^= UInt64(rowBase[offset])
                    hash = hash &* 1_099_511_628_211
                }
                hashes.append(hash)
            }
        }
        return hashes
    }

    private static func containsContiguousSequence(
        _ needle: [UInt64],
        in haystack: [UInt64]
    ) -> Bool {
        guard !needle.isEmpty, needle.count <= haystack.count else { return false }
        if needle.count == 1 {
            return haystack.contains(needle[0])
        }

        for start in 0...(haystack.count - needle.count) {
            var matches = true
            for offset in 0..<needle.count where haystack[start + offset] != needle[offset] {
                matches = false
                break
            }
            if matches {
                return true
            }
        }
        return false
    }
}
