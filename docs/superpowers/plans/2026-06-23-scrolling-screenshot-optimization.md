# Scrolling Screenshot Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Improve VoxFlow scrolling screenshot reliability with band-voted stitching, stable-frame checksum capture, visible failure states, sticky-header / scrollbar exclusion, and optional auto-scroll controls.

**Architecture:** Keep the current `VoxFlowScreenshotKit` capture flow, but split scroll-capture intelligence into small value types around frame analysis, shift confidence, stitch exclusions, and auto-scroll control. The controller remains the session coordinator; the stitcher owns image alignment and row composition; HUD/preview panels only render state and controls.

**Tech Stack:** Swift 6, AppKit, ScreenCaptureKit, Vision `VNTranslationalImageRegistrationRequest`, CoreGraphics, XCTest, SwiftPM.

---

## Scope And Policy

This plan assumes the product decision is to allow GPLv3 code reuse for scroll-capture work. The cleanest path is to switch the whole project license from MIT to GPLv3 before copying or adapting more GPLv3 code from macshot or ShareX.

If the project must remain MIT, do not copy GPLv3 implementation code. In that case, implement the same behavior using clean-room code based on public ideas and prefer MIT / Apache references such as ScrollSnap, PGSSoft/scrollscreenshot, and OpenStitching.

## Reference Projects

- macshot: GPLv3. Use as the primary source for auto-scroll, sticky-header exclusion, scrollbar exclusion, settled-frame behavior, and scroll HUD interaction. Keep source URL, upstream commit, license, copied file list, and modification notes.
- ShareX: GPLv3. Use for product-level failure status model only unless the project is already GPLv3.
- ScrollSnap: MIT. Use for band-voted alignment behavior and dynamic-content tolerance ideas. Preserve MIT attribution if code is copied or adapted.
- PGSSoft/scrollscreenshot: MIT. Use for auto-scroll concepts such as count, direction, inertia, and stitch mode.
- OpenStitching/stitching: Apache-2.0. Use as background for confidence-gated stitching; do not introduce Python/OpenCV into VoxFlow for this feature.

## Current Code Baseline

Current implementation:

- `Sources/VoxFlowScreenshotKit/Capture/ScrollingScreenshotController.swift`
  - Starts a session.
  - Captures a first frame.
  - Installs scroll, key, and mouse monitors.
  - Polls every `pollingInterval`.
  - Captures region frames through `ScrollingScreenshotRegionCapturer.capture`.
  - Finishes on Return / keypad Enter / double-click.
- `Sources/VoxFlowScreenshotKit/Capture/ScrollingScreenshotStitcher.swift`
  - Uses one full-frame `VNTranslationalImageRegistrationRequest`.
  - Appends bottom rows for downward scroll.
  - Prepends top rows for upward scroll.
  - Does not track confidence, failed matches, sticky regions, or scrollbars.
- `Sources/VoxFlowScreenshotKit/Capture/ScrollingScreenshotHUDPanel.swift`
  - Shows only cancel and finish buttons.
  - `update(image:scale:)` does not surface frame count, height, status, or auto-scroll controls.
- `Sources/VoxFlowScreenshotKit/Capture/ScrollingScreenshotPreviewPanel.swift`
  - Shows live preview and scrolls to top/bottom based on direction.
- `Tests/VoxFlowScreenshotKitTests/ScrollingScreenshotStitcherTests.swift`
  - Covers simple append/prepend and default Vision shift direction.
- `Tests/VoxFlowScreenshotKitTests/ScrollingScreenshotControllerTests.swift`
  - Covers finish, cancel, latest-frame capture, and polling.

## Target User Experience

Manual mode remains the default.

When a user starts a scrolling screenshot:

1. VoxFlow captures the selected region.
2. A HUD appears near the selection.
3. A preview panel appears beside the selection when space allows.
4. The user can scroll manually; VoxFlow captures settled frames and stitches confident shifts.
5. The HUD shows status:
   - `已拼 N 帧 · H px`
   - `匹配不稳定`
   - `已到末尾`
   - `已达高度上限`
6. The user can click auto-scroll.
7. Auto-scroll starts only when Accessibility permission is available.
8. Auto-scroll can be paused from the HUD.
9. Continuous zero shifts, repeated failed matching, or max height pause auto-scroll without discarding the current result.
10. The user clicks finish to accept the current stitched image.

## File Structure

Modify:

- `LICENSE`
  - Switch root project license to GPLv3 if the user approves project-wide GPLv3.
- `README.md`
  - Update license badge and license section.
- `README_EN.md`
  - Update license badge and license section.
- `docs/third-party-licenses.md`
  - Extend GPLv3 attribution and source list for copied / adapted scroll-capture code.
- `Sources/VoxFlowScreenshotKit/Capture/ScrollingScreenshotController.swift`
  - Add session state, stable-frame capture, failure counters, auto-scroll lifecycle, and status propagation.
- `Sources/VoxFlowScreenshotKit/Capture/ScrollingScreenshotStitcher.swift`
  - Add shift confidence, band-voted detection, sticky-header and scrollbar exclusion, and status returns.
- `Sources/VoxFlowScreenshotKit/Capture/ScrollingScreenshotHUDPanel.swift`
  - Add status label, frame/height display, auto-scroll button, pause state, and permission message hook.
- `Sources/VoxFlowScreenshotKit/Capture/ScrollingScreenshotPreviewPanel.swift`
  - Keep behavior, adjust only if final stitch status needs preview anchor updates.
- `Tests/VoxFlowScreenshotKitTests/ScrollingScreenshotStitcherTests.swift`
  - Add band voting, confidence, sticky-header, and scrollbar tests.
- `Tests/VoxFlowScreenshotKitTests/ScrollingScreenshotControllerTests.swift`
  - Add stable-frame, failure-state, max-height, auto-scroll state, and permission fallback tests.
- `Tests/VoxFlowScreenshotKitTests/ScrollingScreenshotPanelLayoutTests.swift`
  - Add HUD layout tests for the new auto-scroll button and status label.

Create:

- `Sources/VoxFlowScreenshotKit/Capture/ScrollingScreenshotFrameAnalysis.swift`
  - Small value types for checksums, shift confidence, match failures, detected exclusions, and HUD status.
- `Sources/VoxFlowScreenshotKit/Capture/ScrollingScreenshotAutoScroller.swift`
  - Protocol and AppKit/CoreGraphics implementation for Accessibility permission checks and synthetic scroll events.
- `Tests/VoxFlowScreenshotKitTests/ScrollingScreenshotFrameAnalysisTests.swift`
  - Unit tests for value-type state transitions and status classification.
- `Tests/VoxFlowScreenshotKitTests/ScrollingScreenshotAutoScrollerTests.swift`
  - Unit tests with fake auto-scroll driver.

## Core Types To Add

Add this file:

`Sources/VoxFlowScreenshotKit/Capture/ScrollingScreenshotFrameAnalysis.swift`

```swift
import CoreGraphics
import Foundation

public struct ScrollingScreenshotFrameChecksum: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let bytesPerRow: Int
    public let value: UInt64

    public init(width: Int, height: Int, bytesPerRow: Int, value: UInt64) {
        self.width = width
        self.height = height
        self.bytesPerRow = bytesPerRow
        self.value = value
    }
}

public enum ScrollingScreenshotMatchFailureReason: Equatable, Sendable {
    case captureUnavailable
    case frameSizeChanged
    case duplicateFrame
    case shiftNotDetected
    case shiftTooSmall(Int)
    case bandVoteDisagreed
}

public enum ScrollingScreenshotCaptureHealth: Equatable, Sendable {
    case good
    case unstable(reason: ScrollingScreenshotMatchFailureReason, consecutiveFailures: Int)
    case paused(reason: ScrollingScreenshotMatchFailureReason, consecutiveFailures: Int)
    case reachedEnd
    case reachedHeightLimit
}

public struct ScrollingScreenshotShiftEstimate: Equatable, Sendable {
    public let rows: Int
    public let agreeingBandCount: Int
    public let totalBandCount: Int
    public let excludedTopRows: Int
    public let excludedRightColumns: Int

    public var confidence: Double {
        guard totalBandCount > 0 else { return 0 }
        return Double(agreeingBandCount) / Double(totalBandCount)
    }

    public init(
        rows: Int,
        agreeingBandCount: Int,
        totalBandCount: Int,
        excludedTopRows: Int = 0,
        excludedRightColumns: Int = 0
    ) {
        self.rows = rows
        self.agreeingBandCount = agreeingBandCount
        self.totalBandCount = totalBandCount
        self.excludedTopRows = excludedTopRows
        self.excludedRightColumns = excludedRightColumns
    }
}

public struct ScrollingScreenshotStitchResult: Equatable, @unchecked Sendable {
    public let image: CGImage?
    public let estimate: ScrollingScreenshotShiftEstimate?
    public let failureReason: ScrollingScreenshotMatchFailureReason?

    public static func stitched(_ image: CGImage, estimate: ScrollingScreenshotShiftEstimate) -> Self {
        Self(image: image, estimate: estimate, failureReason: nil)
    }

    public static func skipped(_ reason: ScrollingScreenshotMatchFailureReason) -> Self {
        Self(image: nil, estimate: nil, failureReason: reason)
    }
}

public struct ScrollingScreenshotSessionStatus: Equatable, Sendable {
    public let stripCount: Int
    public let pixelHeight: Int
    public let health: ScrollingScreenshotCaptureHealth
    public let isAutoScrolling: Bool

    public init(
        stripCount: Int,
        pixelHeight: Int,
        health: ScrollingScreenshotCaptureHealth,
        isAutoScrolling: Bool
    ) {
        self.stripCount = stripCount
        self.pixelHeight = pixelHeight
        self.health = health
        self.isAutoScrolling = isAutoScrolling
    }
}
```

Add this file:

`Sources/VoxFlowScreenshotKit/Capture/ScrollingScreenshotAutoScroller.swift`

```swift
import AppKit
import CoreGraphics
import Foundation

@MainActor
public protocol ScrollingScreenshotAutoScrolling: AnyObject {
    var hasAccessibilityPermission: Bool { get }
    func postScrollTick(lines: Int32)
}

@MainActor
public final class AppKitScrollingScreenshotAutoScroller: ScrollingScreenshotAutoScrolling {
    public init() {}

    public var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    public func postScrollTick(lines: Int32) {
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 1,
            wheel1: -abs(lines),
            wheel2: 0,
            wheel3: 0
        ) else {
            return
        }
        event.post(tap: .cghidEventTap)
    }
}
```

## Implementation Tasks

### Task 0: Switch Root License To GPLv3

**Files:**

- Modify: `LICENSE`
- Modify: `README.md`
- Modify: `README_EN.md`
- Modify: `docs/third-party-licenses.md`

- [x] **Step 0.1: Confirm project-level GPLv3 decision**

Proceed only if the product owner confirms the whole distributed VoxFlow app may be GPLv3. The current repository root is MIT, while copied / adapted scroll-capture behavior is already documented as GPLv3-scoped.

- [x] **Step 0.2: Replace root license text**

Replace `LICENSE` with the GPLv3 text already present in `Packages/VoxFlowVoiceCorrectionKit/COPYING`. Keep the root copyright header in a short note:

```text
VoxFlow
Copyright (C) 2026 VoxFlow contributors

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later
version.
```

Then include the full GPLv3 body.

- [x] **Step 0.3: Update README license wording**

In `README.md` and `README_EN.md`, change the badge text from `open source` to `GPLv3` and add a short section:

```markdown
## 开源许可证

VoxFlow 以 GPLv3 分发。第三方组件仍保留各自许可证和归属说明，详见 `docs/third-party-licenses.md`。
```

For English:

```markdown
## License

VoxFlow is distributed under GPLv3. Third-party components keep their original
license notices and attribution. See `docs/third-party-licenses.md`.
```

- [x] **Step 0.4: Extend third-party attribution**

In `docs/third-party-licenses.md`, add a subsection under `sw33tLie/macshot`:

```markdown
### Scroll Capture Optimization Follow-up

- Copied / adapted behavior:
  - settled frame capture using CPU-backed frame comparison;
  - continuous match-failure tracking;
  - sticky header exclusion;
  - scrollbar/right-margin exclusion;
  - synthetic auto-scroll button behavior;
  - auto-scroll stop-on-zero-shift behavior.
- Local target files:
  - `Sources/VoxFlowScreenshotKit/Capture/ScrollingScreenshotController.swift`
  - `Sources/VoxFlowScreenshotKit/Capture/ScrollingScreenshotStitcher.swift`
  - `Sources/VoxFlowScreenshotKit/Capture/ScrollingScreenshotHUDPanel.swift`
  - `Sources/VoxFlowScreenshotKit/Capture/ScrollingScreenshotAutoScroller.swift`
  - `Sources/VoxFlowScreenshotKit/Capture/ScrollingScreenshotFrameAnalysis.swift`
```

- [x] **Step 0.5: Verify docs**

Run:

```bash
rg -n "MIT License|license-open source|open source-10B981|GPLv3|GNU GENERAL PUBLIC LICENSE" LICENSE README.md README_EN.md docs/third-party-licenses.md
```

Expected:

- `LICENSE` contains `GNU GENERAL PUBLIC LICENSE`.
- README files mention GPLv3.
- No README badge still says `license-open source`.

### Task 1: Add Frame Analysis Types

**Files:**

- Create: `Sources/VoxFlowScreenshotKit/Capture/ScrollingScreenshotFrameAnalysis.swift`
- Test: `Tests/VoxFlowScreenshotKitTests/ScrollingScreenshotFrameAnalysisTests.swift`

- [x] **Step 1.1: Write tests for confidence and status values**

Create `Tests/VoxFlowScreenshotKitTests/ScrollingScreenshotFrameAnalysisTests.swift`:

```swift
import XCTest
@testable import VoxFlowScreenshotKit

final class ScrollingScreenshotFrameAnalysisTests: XCTestCase {
    func testShiftEstimateConfidenceUsesAgreeingBandRatio() {
        let estimate = ScrollingScreenshotShiftEstimate(
            rows: 42,
            agreeingBandCount: 4,
            totalBandCount: 5,
            excludedTopRows: 12,
            excludedRightColumns: 8
        )

        XCTAssertEqual(estimate.confidence, 0.8, accuracy: 0.0001)
        XCTAssertEqual(estimate.rows, 42)
        XCTAssertEqual(estimate.excludedTopRows, 12)
        XCTAssertEqual(estimate.excludedRightColumns, 8)
    }

    func testSessionStatusTracksUnstableFailure() {
        let status = ScrollingScreenshotSessionStatus(
            stripCount: 3,
            pixelHeight: 1800,
            health: .unstable(reason: .bandVoteDisagreed, consecutiveFailures: 2),
            isAutoScrolling: false
        )

        XCTAssertEqual(status.stripCount, 3)
        XCTAssertEqual(status.pixelHeight, 1800)
        XCTAssertEqual(status.health, .unstable(reason: .bandVoteDisagreed, consecutiveFailures: 2))
        XCTAssertFalse(status.isAutoScrolling)
    }

    func testStitchResultSkippedStoresFailureReason() {
        let result = ScrollingScreenshotStitchResult.skipped(.shiftTooSmall(2))

        XCTAssertNil(result.image)
        XCTAssertNil(result.estimate)
        XCTAssertEqual(result.failureReason, .shiftTooSmall(2))
    }
}
```

- [x] **Step 1.2: Run failing tests**

Run:

```bash
swift test --filter ScrollingScreenshotFrameAnalysisTests
```

Expected: FAIL because `ScrollingScreenshotFrameAnalysis.swift` does not exist.

- [x] **Step 1.3: Add frame analysis file**

Create `Sources/VoxFlowScreenshotKit/Capture/ScrollingScreenshotFrameAnalysis.swift` using the exact code from **Core Types To Add**.

- [x] **Step 1.4: Run tests**

Run:

```bash
swift test --filter ScrollingScreenshotFrameAnalysisTests
```

Expected: PASS.

### Task 2: Add Band-Voted Shift Detection

**Files:**

- Modify: `Sources/VoxFlowScreenshotKit/Capture/ScrollingScreenshotStitcher.swift`
- Test: `Tests/VoxFlowScreenshotKitTests/ScrollingScreenshotStitcherTests.swift`

- [x] **Step 2.1: Add tests for band voting**

Append these tests to `ScrollingScreenshotStitcherTests`:

```swift
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

    XCTAssertEqual(estimate.rows, 12, accuracy: 3)
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

func testAppendReturnsSkippedWhenBandVoteDisagrees() {
    let first = makePatternImage(width: 80, height: 150)
    let second = makePatternImage(width: 80, height: 150)
    let stitcher = ScrollingScreenshotStitcher(
        shiftEstimator: { _, _ in nil }
    )

    _ = stitcher.start(with: first)
    let result = stitcher.appendAnalyzed(second)

    XCTAssertNil(result.image)
    XCTAssertEqual(result.failureReason, .bandVoteDisagreed)
}
```

- [x] **Step 2.2: Run failing tests**

Run:

```bash
swift test --filter ScrollingScreenshotStitcherTests
```

Expected: FAIL because `detectVerticalShiftEstimate`, `appendAnalyzed`, and the new initializer do not exist.

- [x] **Step 2.3: Add shift configuration and estimator APIs**

In `ScrollingScreenshotStitcher.swift`, add near the top:

```swift
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
```

Replace the stitcher stored detector shape with:

```swift
public final class ScrollingScreenshotStitcher {
    public typealias ShiftDetector = (_ current: CGImage, _ previous: CGImage) -> Int?
    public typealias ShiftEstimator = (_ current: CGImage, _ previous: CGImage) -> ScrollingScreenshotShiftEstimate?

    private let shiftEstimator: ShiftEstimator
    private(set) public var currentImage: CGImage?
    private(set) var lastScrollDirection: ScrollingScreenshotScrollDirection?
    private var previousFrame: CGImage?

    public convenience init(shiftDetector: @escaping ShiftDetector = ScrollingScreenshotStitcher.detectVerticalShift) {
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
}
```

- [x] **Step 2.4: Add analyzed append while preserving old append**

In `ScrollingScreenshotStitcher`, keep `append(_:)` for compatibility and route it through the analyzed API:

```swift
@discardableResult
public func append(_ image: CGImage) -> CGImage? {
    appendAnalyzed(image).image
}

@discardableResult
public func appendAnalyzed(_ image: CGImage) -> ScrollingScreenshotStitchResult {
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

    guard let estimate = shiftEstimator(image, previousFrame), estimate.rows != 0 else {
        return .skipped(.bandVoteDisagreed)
    }

    let shift = estimate.rows
    let newRows = min(abs(shift), image.height)
    guard newRows > 0 else {
        return .skipped(.shiftTooSmall(shift))
    }

    let scrollDirection: ScrollingScreenshotScrollDirection = shift > 0 ? .downward : .upward
    let stitched = shift > 0
        ? Self.appendBottomRows(from: image, rowCount: newRows, to: currentImage)
        : Self.prependTopRows(from: image, rowCount: newRows, to: currentImage)

    guard let stitched else {
        return .skipped(.shiftNotDetected)
    }

    self.currentImage = stitched
    self.previousFrame = image
    self.lastScrollDirection = scrollDirection
    return .stitched(stitched, estimate: estimate)
}
```

- [x] **Step 2.5: Add band-voted detection**

Add this static method to `ScrollingScreenshotStitcher`:

```swift
public static func detectVerticalShiftEstimate(
    current: CGImage,
    previous: CGImage,
    configuration: ScrollingScreenshotShiftDetectionConfiguration = .init(),
    excludedTopRows: Int = 0,
    excludedRightColumns: Int = 0,
    bandShiftDetector: ((_ bandIndex: Int, _ currentBand: CGImage, _ previousBand: CGImage) -> Int?)? = nil
) -> ScrollingScreenshotShiftEstimate? {
    guard current.width == previous.width,
          current.height == previous.height else {
        return nil
    }

    let cropTop = min(max(0, excludedTopRows), current.height - 1)
    let cropRight = min(max(0, excludedRightColumns), current.width - 1)
    let cropWidth = current.width - cropRight
    let cropHeight = current.height - cropTop
    guard cropWidth > 20, cropHeight > 20 else { return nil }

    let bandCount = min(configuration.bandCount, max(1, cropHeight / 20))
    let bandHeight = max(20, cropHeight / bandCount)
    var offsets: [Int] = []
    var totalBands = 0

    for bandIndex in 0..<bandCount {
        let originY = cropTop + min(cropHeight - bandHeight, bandIndex * max(1, (cropHeight - bandHeight) / max(1, bandCount - 1)))
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

    guard totalBands > 0, let firstOffset = offsets.first else { return nil }
    var bestGroup: [Int] = []
    for offset in offsets {
        let group = offsets.filter { abs($0 - offset) <= configuration.toleranceRows }
        if group.count > bestGroup.count {
            bestGroup = group
        }
    }

    let requiredAgreement = max(1, Int(ceil(Double(totalBands) * configuration.agreementRatio)))
    guard bestGroup.count >= requiredAgreement else { return nil }

    let average = Double(bestGroup.reduce(0, +)) / Double(bestGroup.count)
    let rows = Int(round(average))
    guard abs(rows) >= configuration.minimumShiftRows else { return nil }

    return ScrollingScreenshotShiftEstimate(
        rows: rows,
        agreeingBandCount: bestGroup.count,
        totalBandCount: totalBands,
        excludedTopRows: excludedTopRows,
        excludedRightColumns: excludedRightColumns
    )
}
```

Use this as the default estimator:

```swift
public init() {
    self.shiftEstimator = { current, previous in
        Self.detectVerticalShiftEstimate(current: current, previous: previous)
    }
}
```

If Swift rejects initializer overload ambiguity, keep only:

```swift
public convenience init() {
    self.init(shiftEstimator: { current, previous in
        Self.detectVerticalShiftEstimate(current: current, previous: previous)
    })
}
```

- [x] **Step 2.6: Run tests**

Run:

```bash
swift test --filter ScrollingScreenshotStitcherTests
```

Expected: PASS.

### Task 3: Stable Frame Checksum Capture

**Files:**

- Modify: `Sources/VoxFlowScreenshotKit/Capture/ScrollingScreenshotController.swift`
- Test: `Tests/VoxFlowScreenshotKitTests/ScrollingScreenshotControllerTests.swift`

- [x] **Step 3.1: Add checksum tests**

Append to `ScrollingScreenshotControllerTests`:

```swift
func testCaptureFrameWaitsForStableChecksum() async {
    let first = makeImage(width: 10, height: 10, seed: 1)
    let second = makeImage(width: 10, height: 10, seed: 2)
    let stable = makeImage(width: 10, height: 10, seed: 3)
    var frames = [first, second, stable, stable]
    let eventMonitor = FakeScrollingScreenshotInputMonitor()
    let controller = ScrollingScreenshotController(
        request: makeRequest(),
        regionCapture: { _ in frames.removeFirst() },
        eventMonitor: eventMonitor,
        confirmationPresenter: FakeScrollingScreenshotConfirmationPresenter()
    )

    let captured = await controller.captureStableFrameForTesting(maxAttempts: 4, initialDelayNanoseconds: 1)

    XCTAssertEqual(captured?.width, stable.width)
    XCTAssertEqual(captured?.height, stable.height)
}

func testCaptureFrameReturnsLastFrameWhenNoStablePairAppears() async {
    let first = makeImage(width: 10, height: 10, seed: 1)
    let second = makeImage(width: 10, height: 10, seed: 2)
    var frames = [first, second]
    let eventMonitor = FakeScrollingScreenshotInputMonitor()
    let controller = ScrollingScreenshotController(
        request: makeRequest(),
        regionCapture: { _ in frames.isEmpty ? second : frames.removeFirst() },
        eventMonitor: eventMonitor,
        confirmationPresenter: FakeScrollingScreenshotConfirmationPresenter()
    )

    let captured = await controller.captureStableFrameForTesting(maxAttempts: 2, initialDelayNanoseconds: 1)

    XCTAssertEqual(captured?.width, second.width)
    XCTAssertEqual(captured?.height, second.height)
}
```

- [x] **Step 3.2: Run failing tests**

Run:

```bash
swift test --filter ScrollingScreenshotControllerTests
```

Expected: FAIL because `captureStableFrameForTesting` does not exist.

- [x] **Step 3.3: Add checksum helper**

In `ScrollingScreenshotController.swift`, replace the body of `captureFrame()` with a call to a new stable-frame function:

```swift
private func captureFrame() async -> CGImage? {
    await captureStableFrame(maxAttempts: 10, initialDelayNanoseconds: 30_000_000)
}
```

Add this method:

```swift
func captureStableFrameForTesting(
    maxAttempts: Int,
    initialDelayNanoseconds: UInt64
) async -> CGImage? {
    await captureStableFrame(maxAttempts: maxAttempts, initialDelayNanoseconds: initialDelayNanoseconds)
}
```

Add the private implementation:

```swift
private func captureStableFrame(
    maxAttempts: Int,
    initialDelayNanoseconds: UInt64
) async -> CGImage? {
    var previousChecksum: ScrollingScreenshotFrameChecksum?
    var previousFrame: CGImage?
    var delay = initialDelayNanoseconds

    for _ in 0..<max(1, maxAttempts) {
        guard let current = await regionCapture(request) else {
            try? await Task.sleep(nanoseconds: delay)
            delay = min(delay * 3 / 2, 80_000_000)
            continue
        }

        guard let checksum = Self.checksum(for: current) else {
            previousFrame = current
            try? await Task.sleep(nanoseconds: delay)
            delay = min(delay * 3 / 2, 80_000_000)
            continue
        }

        if checksum == previousChecksum {
            return current
        }

        previousChecksum = checksum
        previousFrame = current
        try? await Task.sleep(nanoseconds: delay)
        delay = min(delay * 3 / 2, 80_000_000)
    }

    return previousFrame
}
```

Add the checksum implementation:

```swift
static func checksum(for image: CGImage) -> ScrollingScreenshotFrameChecksum? {
    guard let data = image.dataProvider?.data as Data? else { return nil }
    let rowLength = image.width * 4
    guard image.bitsPerPixel == 32,
          image.bytesPerRow >= rowLength,
          data.count >= image.bytesPerRow * image.height else {
        return nil
    }

    var hash: UInt64 = 14_695_981_039_346_656_037
    let prime: UInt64 = 1_099_511_628_211
    data.withUnsafeBytes { bytes in
        guard let base = bytes.bindMemory(to: UInt8.self).baseAddress else { return }
        for row in 0..<image.height {
            let rowBase = base.advanced(by: row * image.bytesPerRow)
            for col in 0..<rowLength {
                hash ^= UInt64(rowBase[col])
                hash = hash &* prime
            }
        }
    }

    return ScrollingScreenshotFrameChecksum(
        width: image.width,
        height: image.height,
        bytesPerRow: rowLength,
        value: hash
    )
}
```

- [x] **Step 3.4: Run tests**

Run:

```bash
swift test --filter ScrollingScreenshotControllerTests
```

Expected: PASS.

### Task 4: Continuous Failure State And HUD Status

**Files:**

- Modify: `Sources/VoxFlowScreenshotKit/Capture/ScrollingScreenshotController.swift`
- Modify: `Sources/VoxFlowScreenshotKit/Capture/ScrollingScreenshotHUDPanel.swift`
- Test: `Tests/VoxFlowScreenshotKitTests/ScrollingScreenshotControllerTests.swift`
- Test: `Tests/VoxFlowScreenshotKitTests/ScrollingScreenshotPanelLayoutTests.swift`

- [x] **Step 4.1: Add controller failure-state tests**

Append to `ScrollingScreenshotControllerTests`:

```swift
func testConsecutiveFailedMatchesUpdateStatus() async {
    let firstFrame = makeImage(width: 2, height: 3)
    let failedFrame = makeImage(width: 2, height: 3, seed: 100)
    let eventMonitor = FakeScrollingScreenshotInputMonitor()
    let stitcher = ScrollingScreenshotStitcher(shiftEstimator: { _, _ in nil })
    var statuses: [ScrollingScreenshotSessionStatus] = []
    var captureCount = 0
    let controller = ScrollingScreenshotController(
        request: makeRequest(),
        regionCapture: { _ in
            captureCount += 1
            return captureCount <= 2 ? firstFrame : failedFrame
        },
        stitcher: stitcher,
        pollingInterval: 0.05,
        eventMonitor: eventMonitor,
        confirmationPresenter: FakeScrollingScreenshotConfirmationPresenter()
    )
    controller.onStatusChangedForTesting = { statuses.append($0) }

    let task = Task { await controller.start() }
    await eventMonitor.waitUntilReady()
    let deadline = Date().addingTimeInterval(1)
    while statuses.allSatisfy({ status in
        if case .unstable = status.health { return false }
        return true
    }), Date() < deadline {
        try? await Task.sleep(nanoseconds: 10_000_000)
    }

    eventMonitor.emitGlobalKeyDown(keyCode: 36)
    _ = await task.value

    XCTAssertTrue(statuses.contains { status in
        if case .unstable(reason: .bandVoteDisagreed, consecutiveFailures: _) = status.health {
            return true
        }
        return false
    })
}
```

- [x] **Step 4.2: Add HUD layout test**

Append to `ScrollingScreenshotPanelLayoutTests`:

```swift
@MainActor
func testHUDExpandsForStatusAndAutoScrollButton() {
    let panel = ScrollingScreenshotHUDPanel()
    let image = makeImage(width: 120, height: 240)

    panel.update(
        status: ScrollingScreenshotSessionStatus(
            stripCount: 3,
            pixelHeight: 720,
            health: .unstable(reason: .bandVoteDisagreed, consecutiveFailures: 2),
            isAutoScrolling: false
        ),
        image: image,
        scale: 2
    )

    XCTAssertGreaterThan(panel.frame.width, 76)
    XCTAssertGreaterThanOrEqual(panel.frame.height, 44)
}
```

If `makeImage` is local to another test file, add an identical private helper to `ScrollingScreenshotPanelLayoutTests`.

- [x] **Step 4.3: Run failing tests**

Run:

```bash
swift test --filter ScrollingScreenshotControllerTests
swift test --filter ScrollingScreenshotPanelLayoutTests
```

Expected: FAIL because status callbacks and HUD status update do not exist.

- [x] **Step 4.4: Add controller status state**

In `ScrollingScreenshotController`, add stored properties:

```swift
private var stripCount = 1
private var consecutiveFailureCount = 0
private let maxConsecutiveFailuresBeforePause = 6
var onStatusChangedForTesting: ((ScrollingScreenshotSessionStatus) -> Void)?
```

Add:

```swift
private func currentStatus(
    health: ScrollingScreenshotCaptureHealth,
    isAutoScrolling: Bool = false
) -> ScrollingScreenshotSessionStatus {
    ScrollingScreenshotSessionStatus(
        stripCount: stripCount,
        pixelHeight: stitcher.currentImage?.height ?? 0,
        health: health,
        isAutoScrolling: isAutoScrolling
    )
}

private func publishStatus(_ health: ScrollingScreenshotCaptureHealth) {
    let status = currentStatus(health: health)
    hudPanel?.update(status: status, image: stitcher.currentImage, scale: request.selection.displayScale)
    onStatusChangedForTesting?(status)
}
```

Replace `captureAndAppendFrame()` with:

```swift
private func captureAndAppendFrame() async {
    guard let frame = await captureFrame() else {
        recordFailedAppend(.captureUnavailable)
        return
    }

    let result = stitcher.appendAnalyzed(frame)
    if let stitched = result.image {
        stripCount += 1
        consecutiveFailureCount = 0
        updatePanels(image: stitched, scrollDirection: stitcher.lastScrollDirection)
        publishStatus(stitched.height >= maxPixelHeight ? .reachedHeightLimit : .good)
        if stitched.height >= maxPixelHeight {
            finish()
        }
    } else {
        recordFailedAppend(result.failureReason ?? .shiftNotDetected)
    }
}

private func recordFailedAppend(_ reason: ScrollingScreenshotMatchFailureReason) {
    consecutiveFailureCount += 1
    let health: ScrollingScreenshotCaptureHealth = consecutiveFailureCount >= maxConsecutiveFailuresBeforePause
        ? .paused(reason: reason, consecutiveFailures: consecutiveFailureCount)
        : .unstable(reason: reason, consecutiveFailures: consecutiveFailureCount)
    publishStatus(health)
}
```

In `start()`, after `stitcher.start(with:)`, initialize and publish:

```swift
stripCount = 1
consecutiveFailureCount = 0
publishStatus(.good)
```

- [x] **Step 4.5: Update HUD API**

In `ScrollingScreenshotHUDPanel.swift`, add an auto-scroll button and status label:

```swift
private let autoScrollButton = NSButton()
private let statusLabel = NSTextField(labelWithString: "")
var onToggleAutoScroll: (() -> Void)?
```

Configure `autoScrollButton` with SF Symbol `play.fill`, tooltip `自动滚动`, and action:

```swift
@objc private func autoScrollClicked() {
    onToggleAutoScroll?()
}
```

Add this `ScrollingScreenshotHUDPanel` method:

```swift
func update(status: ScrollingScreenshotSessionStatus, image: CGImage?, scale: CGFloat) {
    hudView.update(status: status, image: image, scale: scale)
    contentView?.frame = CGRect(origin: .zero, size: hudView.frame.size)
    hudView.frame.origin = .zero
    setFrame(CGRect(origin: frame.origin, size: hudView.frame.size), display: true)
}
```

Keep the old method as compatibility:

```swift
func update(image: CGImage, scale: CGFloat) {
    update(
        status: ScrollingScreenshotSessionStatus(
            stripCount: 1,
            pixelHeight: image.height,
            health: .good,
            isAutoScrolling: false
        ),
        image: image,
        scale: scale
    )
}
```

Use this status text mapping:

```swift
private func statusText(for status: ScrollingScreenshotSessionStatus) -> String {
    switch status.health {
    case .good:
        return "已拼 \(status.stripCount) 帧 · \(status.pixelHeight) px"
    case .unstable:
        return "匹配不稳定 · 已拼 \(status.stripCount) 帧"
    case .paused:
        return "已暂停 · 匹配不稳定"
    case .reachedEnd:
        return "已到末尾 · \(status.pixelHeight) px"
    case .reachedHeightLimit:
        return "已达高度上限 · \(status.pixelHeight) px"
    }
}
```

- [x] **Step 4.6: Run tests**

Run:

```bash
swift test --filter ScrollingScreenshotControllerTests
swift test --filter ScrollingScreenshotPanelLayoutTests
```

Expected: PASS.

### Task 5: Sticky Header And Scrollbar Exclusion

**Files:**

- Modify: `Sources/VoxFlowScreenshotKit/Capture/ScrollingScreenshotStitcher.swift`
- Test: `Tests/VoxFlowScreenshotKitTests/ScrollingScreenshotStitcherTests.swift`

- [x] **Step 5.1: Add sticky-header tests**

Append to `ScrollingScreenshotStitcherTests`:

```swift
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
        maxHeaderRatio: 0.6
    )

    XCTAssertEqual(rows, 2)
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
```

If `makeImage(width:height:pixel:)` is private and not available to this test body, move it from private to file-private within the same test file. Keep helpers test-only.

- [x] **Step 5.2: Run failing tests**

Run:

```bash
swift test --filter ScrollingScreenshotStitcherTests
```

Expected: FAIL because sticky-header and right-margin detectors do not exist.

- [x] **Step 5.3: Add detector functions**

Add to `ScrollingScreenshotStitcher`:

```swift
public static func detectStickyTopRows(
    current: CGImage,
    previous: CGImage,
    maxHeaderRatio: Double = 0.6
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
    let bytesPerPixel = 4
    let rowLength = width * bytesPerPixel
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

    return stickyRows >= 10 ? stickyRows : 0
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
    let scanColumns = min(maxScanColumns, width / 4)
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
```

- [x] **Step 5.4: Feed exclusions into shift estimate**

Add stored exclusion state in `ScrollingScreenshotStitcher`:

```swift
private var stickyTopRows = 0
private var rightMarginColumns = 0
private var hasDetectedExclusions = false
```

In `start(with:)`, reset:

```swift
stickyTopRows = 0
rightMarginColumns = 0
hasDetectedExclusions = false
```

Before estimating shift in `appendAnalyzed(_:)`, add:

```swift
if !hasDetectedExclusions {
    stickyTopRows = Self.detectStickyTopRows(current: image, previous: previousFrame)
    rightMarginColumns = Self.detectRightMarginColumns(current: image, previous: previousFrame)
    hasDetectedExclusions = true
}
```

If using the default estimator, call:

```swift
let estimate = Self.detectVerticalShiftEstimate(
    current: image,
    previous: previousFrame,
    excludedTopRows: stickyTopRows,
    excludedRightColumns: rightMarginColumns
)
```

To keep injected `shiftEstimator` tests working, introduce an internal helper:

```swift
private func estimateShift(current: CGImage, previous: CGImage) -> ScrollingScreenshotShiftEstimate? {
    if let estimate = shiftEstimator(current, previous) {
        return estimate
    }
    return Self.detectVerticalShiftEstimate(
        current: current,
        previous: previous,
        excludedTopRows: stickyTopRows,
        excludedRightColumns: rightMarginColumns
    )
}
```

Then use `estimateShift(current: image, previous: previousFrame)`.

- [x] **Step 5.5: Run tests**

Run:

```bash
swift test --filter ScrollingScreenshotStitcherTests
```

Expected: PASS.

### Task 6: Auto-Scroll Button And Driver

**Files:**

- Create: `Sources/VoxFlowScreenshotKit/Capture/ScrollingScreenshotAutoScroller.swift`
- Modify: `Sources/VoxFlowScreenshotKit/Capture/ScrollingScreenshotController.swift`
- Modify: `Sources/VoxFlowScreenshotKit/Capture/ScrollingScreenshotHUDPanel.swift`
- Test: `Tests/VoxFlowScreenshotKitTests/ScrollingScreenshotAutoScrollerTests.swift`
- Test: `Tests/VoxFlowScreenshotKitTests/ScrollingScreenshotControllerTests.swift`

- [x] **Step 6.1: Add fake auto-scroller tests**

Create `Tests/VoxFlowScreenshotKitTests/ScrollingScreenshotAutoScrollerTests.swift`:

```swift
import XCTest
@testable import VoxFlowScreenshotKit

@MainActor
final class ScrollingScreenshotAutoScrollerTests: XCTestCase {
    func testFakeAutoScrollerRecordsScrollTicks() {
        let scroller = FakeScrollingScreenshotAutoScroller(hasPermission: true)

        scroller.postScrollTick(lines: 2)
        scroller.postScrollTick(lines: 4)

        XCTAssertEqual(scroller.postedLines, [2, 4])
    }
}

@MainActor
final class FakeScrollingScreenshotAutoScroller: ScrollingScreenshotAutoScrolling {
    var hasAccessibilityPermission: Bool
    private(set) var postedLines: [Int32] = []

    init(hasPermission: Bool) {
        self.hasAccessibilityPermission = hasPermission
    }

    func postScrollTick(lines: Int32) {
        postedLines.append(lines)
    }
}
```

- [x] **Step 6.2: Add controller auto-scroll tests**

Append to `ScrollingScreenshotControllerTests`:

```swift
func testAutoScrollDoesNotStartWithoutAccessibilityPermission() async {
    let image = makeImage(width: 120, height: 160)
    let eventMonitor = FakeScrollingScreenshotInputMonitor()
    let autoScroller = FakeScrollingScreenshotAutoScroller(hasPermission: false)
    let controller = ScrollingScreenshotController(
        request: makeRequest(),
        regionCapture: { _ in image },
        eventMonitor: eventMonitor,
        confirmationPresenter: FakeScrollingScreenshotConfirmationPresenter(),
        autoScroller: autoScroller
    )

    let task = Task { await controller.start() }
    await eventMonitor.waitUntilReady()

    controller.toggleAutoScrollForTesting()
    eventMonitor.emitGlobalKeyDown(keyCode: 36)
    _ = await task.value

    XCTAssertTrue(autoScroller.postedLines.isEmpty)
}

func testAutoScrollPostsTicksWhenPermissionGranted() async {
    let image = makeImage(width: 120, height: 160)
    let eventMonitor = FakeScrollingScreenshotInputMonitor()
    let autoScroller = FakeScrollingScreenshotAutoScroller(hasPermission: true)
    let controller = ScrollingScreenshotController(
        request: makeRequest(),
        regionCapture: { _ in image },
        eventMonitor: eventMonitor,
        confirmationPresenter: FakeScrollingScreenshotConfirmationPresenter(),
        autoScroller: autoScroller
    )

    let task = Task { await controller.start() }
    await eventMonitor.waitUntilReady()

    controller.toggleAutoScrollForTesting()
    let deadline = Date().addingTimeInterval(1)
    while autoScroller.postedLines.isEmpty, Date() < deadline {
        try? await Task.sleep(nanoseconds: 10_000_000)
    }

    eventMonitor.emitGlobalKeyDown(keyCode: 36)
    _ = await task.value

    XCTAssertFalse(autoScroller.postedLines.isEmpty)
}
```

- [x] **Step 6.3: Run failing tests**

Run:

```bash
swift test --filter ScrollingScreenshotAutoScrollerTests
swift test --filter ScrollingScreenshotControllerTests
```

Expected: FAIL because the protocol, controller initializer parameter, and toggle method do not exist.

- [x] **Step 6.4: Add auto-scroller file**

Create `Sources/VoxFlowScreenshotKit/Capture/ScrollingScreenshotAutoScroller.swift` using the exact code from **Core Types To Add**.

- [x] **Step 6.5: Wire auto-scroll into controller**

In `ScrollingScreenshotController`, add:

```swift
private let autoScroller: any ScrollingScreenshotAutoScrolling
private var autoScrollTask: Task<Void, Never>?
private var isAutoScrolling = false
```

Extend initializer:

```swift
autoScroller: any ScrollingScreenshotAutoScrolling = AppKitScrollingScreenshotAutoScroller()
```

Assign:

```swift
self.autoScroller = autoScroller
```

In `showPanels(initialImage:)`, connect HUD:

```swift
hud.hudView.onToggleAutoScroll = { [weak self] in self?.toggleAutoScroll() }
```

Add:

```swift
func toggleAutoScrollForTesting() {
    toggleAutoScroll()
}

private func toggleAutoScroll() {
    if isAutoScrolling {
        stopAutoScroll(health: .good)
    } else {
        startAutoScroll()
    }
}

private func startAutoScroll() {
    guard autoScroller.hasAccessibilityPermission else {
        publishStatus(.paused(reason: .captureUnavailable, consecutiveFailures: consecutiveFailureCount))
        return
    }

    isAutoScrolling = true
    publishStatus(.good)
    autoScrollTask = Task { @MainActor [weak self] in
        guard let self else { return }
        while !Task.isCancelled && self.isAutoScrolling && !self.isFinishing {
            self.autoScroller.postScrollTick(lines: 1)
            self.scheduleCapture()
            try? await Task.sleep(nanoseconds: 120_000_000)
        }
    }
}

private func stopAutoScroll(health: ScrollingScreenshotCaptureHealth) {
    isAutoScrolling = false
    autoScrollTask?.cancel()
    autoScrollTask = nil
    publishStatus(health)
}
```

In `cleanupCaptureSession()`:

```swift
stopAutoScroll(health: .good)
```

Avoid publishing after finish by guarding inside `stopAutoScroll`:

```swift
guard !isFinishing else {
    isAutoScrolling = false
    autoScrollTask?.cancel()
    autoScrollTask = nil
    return
}
```

- [x] **Step 6.6: Auto-stop on zero movement and failure**

Add stored properties:

```swift
private var consecutiveZeroShiftCount = 0
private let maxConsecutiveZeroShiftsBeforeEnd = 6
```

In `recordFailedAppend(_:)`, when `reason == .shiftTooSmall(0)` or `.duplicateFrame`, increment zero-shift count:

```swift
if reason == .duplicateFrame || reason == .shiftTooSmall(0) {
    consecutiveZeroShiftCount += 1
    if isAutoScrolling && consecutiveZeroShiftCount >= maxConsecutiveZeroShiftsBeforeEnd {
        stopAutoScroll(health: .reachedEnd)
        return
    }
} else {
    consecutiveZeroShiftCount = 0
}

if isAutoScrolling && consecutiveFailureCount >= maxConsecutiveFailuresBeforePause {
    stopAutoScroll(health: .paused(reason: reason, consecutiveFailures: consecutiveFailureCount))
    return
}
```

On successful stitch, reset:

```swift
consecutiveZeroShiftCount = 0
```

- [x] **Step 6.7: Run tests**

Run:

```bash
swift test --filter ScrollingScreenshotAutoScrollerTests
swift test --filter ScrollingScreenshotControllerTests
swift test --filter ScrollingScreenshotPanelLayoutTests
```

Expected: PASS.

### Task 7: Integration Verification And Manual QA

**Files:**

- Modify only if verification reveals issues in files touched above.

- [x] **Step 7.1: Run screenshot kit tests**

Run:

```bash
swift test --filter VoxFlowScreenshotKitTests
```

Expected: PASS.

- [x] **Step 7.2: Run targeted app bridge tests**

Run:

```bash
swift test --filter VoxFlowInteractiveScreenshotProviderTests
swift test --filter ScreenshotOCRResultPanelPresentationTests
swift test --filter VoxFlowScreenshotImageProviderTests
```

Expected: PASS.

- [x] **Step 7.3: Run full test gate**

Run:

```bash
swift test
```

Expected: PASS with 0 unexpected failures. If unrelated existing migration failures block this command, record the failing test names and prove the screenshot-related filters above pass.

- [x] **Step 7.4: Run build gates**

Run:

```bash
make debug
make build
```

Expected:

- `make debug` passes with warnings treated as errors.
- `make build` produces the release app bundle.

If unrelated worktree changes block these commands, record the exact file, line, and error output in the final report.

- [ ] **Step 7.5: Manual QA using real app**

Launch smoke completed with `make run-dev`: debug bundle built, signed, and opened. The real capture scenarios below still require desktop interaction and remain unchecked until manually verified.

Run:

```bash
make run-dev
```

Manual scenarios:

1. Capture a normal long webpage in Safari or Chrome using manual scroll.
2. Capture a page with sticky top navigation.
3. Capture a page with a visible right scrollbar.
4. Capture a page with animated content or video preview inside the selected region.
5. Start auto-scroll with Accessibility permission granted.
6. Start auto-scroll without Accessibility permission.
7. Press `Esc` during manual capture.
8. Press `Return` during auto-scroll.
9. Reach max height and confirm the capture pauses rather than discarding the image.

Expected:

- Manual scroll remains usable.
- Auto-scroll only starts when permission is available.
- Sticky header is not duplicated.
- Scrollbar changes do not shift the stitch seam.
- Dynamic content produces warning/paused status instead of corrupting the whole image silently.
- Finish returns a `ScrollingScreenshotCaptureResult`.
- OCR/copy/save flow still treats the result as `.scrollingScreenshot`.

## Acceptance Criteria

Functional:

- Band-voted shift detection is the default for scrolling screenshots.
- Stable-frame capture uses checksum comparison instead of direct `dataProvider?.data` equality.
- HUD shows frame count, pixel height, health state, and auto-scroll state.
- Consecutive matching failures are visible to the user.
- Sticky headers are excluded from alignment and do not repeatedly appear in output.
- Right scrollbar / margin movement is excluded from alignment.
- Auto-scroll starts, pauses, and stops from the HUD.
- Auto-scroll gracefully falls back to manual mode when Accessibility permission is missing.
- Existing manual scrolling still works.

Testing:

- `swift test --filter ScrollingScreenshotFrameAnalysisTests` passes.
- `swift test --filter ScrollingScreenshotStitcherTests` passes.
- `swift test --filter ScrollingScreenshotControllerTests` passes.
- `swift test --filter ScrollingScreenshotPanelLayoutTests` passes.
- `swift test --filter ScrollingScreenshotAutoScrollerTests` passes.
- `swift test` passes or unrelated failures are documented with targeted screenshot tests passing.
- `make debug` and `make build` pass or unrelated blockers are documented.

Documentation:

- Root license matches the project-level GPLv3 decision.
- macshot / ShareX / ScrollSnap attribution is updated in `docs/third-party-licenses.md`.
- README and README_EN do not claim a pure MIT project after GPLv3 adoption.

Compatibility:

- The result still flows through `InteractiveScreenshotCaptureResult` as `.scrollingScreenshot`.
- Existing screenshot OCR, copy, save, and record history paths keep working.
- No new runtime dependency is introduced.

## Suggested Commit Split

Use Conventional Commits in Chinese, with the required Codex co-author trailer.

1. `chore(license): 将项目许可证切换为 GPLv3`
2. `feat(screenshot): 增强滚动长图位移检测稳定性`
3. `feat(screenshot): 为滚动长图增加失败状态提示`
4. `feat(screenshot): 排除固定页眉和滚动条干扰`
5. `feat(screenshot): 增加滚动长图自动滚动控制`

Each commit message body should include:

- 改动目标与背景；
- 具体改动文件与行为变化；
- 影响范围与兼容性；
- 验证方式与结果，含未验证项。

## Rollback Plan

If Phase 1 causes regressions:

- Keep the new tests.
- Restore `ScrollingScreenshotStitcher` default initializer to the old single full-frame Vision detector.
- Keep `appendAnalyzed(_:)` as an internal status API but map all skipped results to old `nil` behavior.

If Phase 2 causes over-cropping:

- Add a feature flag in `ScrollingScreenshotShiftDetectionConfiguration`:

```swift
public let exclusionDetectionEnabled: Bool
```

- Default it to `true`.
- Disable only sticky-header/right-margin exclusion while keeping band voting.

If Phase 3 causes target-app scroll issues:

- Keep the HUD button hidden unless `AXIsProcessTrusted()` is true.
- Manual scroll remains the primary path.

## Open Questions

These need a product decision before implementation starts:

1. Should VoxFlow switch the whole root project license to GPLv3 before copying more GPLv3 scroll-capture implementation?
2. Should auto-scroll speed be a hidden fixed value for the first release, or should the HUD expose slow / standard / fast immediately?
3. Should completing a scrolling screenshot show a confirmation panel, or continue returning directly to the existing OCR/copy/save flow?
