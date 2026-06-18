import CoreGraphics
import Foundation

@MainActor
protocol LastResultStoring: AnyObject {
    var lastResultText: String? { get }
    func setLastResultText(_ text: String?)
}

@MainActor
final class InMemoryLastResultStore: LastResultStoring {
    private(set) var lastResultText: String?

    func setLastResultText(_ text: String?) {
        let trimmedText = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        lastResultText = trimmedText?.isEmpty == false ? trimmedText : nil
    }
}

@MainActor
protocol ClipboardImageProviding: AnyObject {
    func currentImage() -> CGImage?
}

@MainActor
protocol TextOCRRecognizing: AnyObject {
    func recognizeText(in image: CGImage) async throws -> String
}

enum PasteLastResultOutcome: Equatable {
    case pastedLastResult
    case pastedOCRText
    case noTextAvailable
    case ocrFailed(String)
    case outputFailed(OutputResult)
}

@MainActor
final class PasteLastResultService {
    private let lastResultStore: any LastResultStoring
    private let clipboardImageProvider: any ClipboardImageProviding
    private let ocrRecognizer: any TextOCRRecognizing
    private let outputService: any OutputService
    private let targetProvider: any DictationTargetProviding
    private let isImageOCREnabled: () -> Bool

    init(
        lastResultStore: any LastResultStoring,
        clipboardImageProvider: any ClipboardImageProviding,
        ocrRecognizer: any TextOCRRecognizing,
        outputService: any OutputService,
        targetProvider: any DictationTargetProviding,
        isImageOCREnabled: @escaping () -> Bool
    ) {
        self.lastResultStore = lastResultStore
        self.clipboardImageProvider = clipboardImageProvider
        self.ocrRecognizer = ocrRecognizer
        self.outputService = outputService
        self.targetProvider = targetProvider
        self.isImageOCREnabled = isImageOCREnabled
    }

    func paste() async -> PasteLastResultOutcome {
        if isImageOCREnabled(), let image = clipboardImageProvider.currentImage() {
            return await pasteOCRText(from: image)
        }

        guard let text = lastResultStore.lastResultText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return .noTextAvailable
        }
        return await pasteText(text, success: .pastedLastResult, shouldRemember: false)
    }

    private func pasteOCRText(from image: CGImage) async -> PasteLastResultOutcome {
        do {
            let text = try await ocrRecognizer
                .recognizeText(in: image)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                return .ocrFailed("未识别到图片文字")
            }
            return await pasteText(text, success: .pastedOCRText, shouldRemember: true)
        } catch {
            return .ocrFailed(error.localizedDescription)
        }
    }

    private func pasteText(
        _ text: String,
        success: PasteLastResultOutcome,
        shouldRemember: Bool
    ) async -> PasteLastResultOutcome {
        let target = targetProvider.currentTarget()
        let result = await outputService.deliver(
            text: text,
            mode: .dictation,
            target: target,
            originalTarget: target
        )
        guard result.isPasteLastResultSuccess else {
            return .outputFailed(result)
        }
        if shouldRemember {
            lastResultStore.setLastResultText(text)
        }
        return success
    }
}

private extension OutputResult {
    var isPasteLastResultSuccess: Bool {
        switch self {
        case .injected, .copied:
            return true
        case .targetChanged, .permissionDenied, .injectionFailed, .copyFailed, .cancelled:
            return false
        }
    }
}
