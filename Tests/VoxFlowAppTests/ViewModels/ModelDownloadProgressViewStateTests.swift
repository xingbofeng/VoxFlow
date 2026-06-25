import XCTest
@testable import VoxFlowApp

final class ModelDownloadProgressViewStateTests: XCTestCase {
    func testDetailTextShowsDownloadedBytesTotalBytesAndPercent() {
        let state = ModelDownloadProgressViewState(
            providerID: "qwen3",
            componentName: "model.safetensors",
            statusText: "下载 model.safetensors",
            fractionCompleted: 0.5,
            bytesWritten: 354_118_472,
            totalBytes: 708_236_945,
            totalModelBytes: 712_777_119,
            speedBytesPerSecond: 5_242_880
        )

        XCTAssertEqual(state.progressValue, 0.5)
        XCTAssertTrue(state.detailText.contains("354.1 MB / 708.2 MB"))
        XCTAssertTrue(state.detailText.contains("50%"))
        XCTAssertTrue(state.detailText.contains("5.2 MB/s"))
        XCTAssertEqual(state.modelSizeText, "模型大小 712.8 MB")
    }

    func testDetailTextEstimatesDownloadedBytesWhenOnlyFractionAndTotalAreKnown() {
        let state = ModelDownloadProgressViewState(
            providerID: "whisper",
            componentName: "下载 Whisper 模型",
            statusText: "下载 Whisper 模型",
            fractionCompleted: 0.25,
            bytesWritten: nil,
            totalBytes: 632_000_000,
            totalModelBytes: 632_000_000,
            speedBytesPerSecond: nil
        )

        XCTAssertEqual(state.detailText, "158 MB / 632 MB · 25%")
        XCTAssertEqual(state.modelSizeText, "模型大小 632 MB")
    }
}
