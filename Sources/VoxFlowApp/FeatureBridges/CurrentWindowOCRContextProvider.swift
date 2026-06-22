import CoreGraphics
import Foundation
import NaturalLanguage
import Vision
import VoxFlowContextBoost

protocol CurrentWindowOCRContextProviding: Sendable {
    func captureContext(for target: DictationTarget?) async -> OCRContextSnapshot?
}

protocol OCRNamedEntityProviding: Sendable {
    func namedEntities(in text: String) -> [NamedEntityCandidate]
}

struct CurrentWindowOCRContextProvider: CurrentWindowOCRContextProviding {
    private let screenshotProvider: any ScreenshotProviding
    private let namedEntityProvider: any OCRNamedEntityProviding
    private let extractor: HotwordExtractor
    private let ranker: HotwordRanker
    private let now: @Sendable () -> Date

    init(
        screenshotProvider: any ScreenshotProviding = SystemScreenshotProvider(),
        namedEntityProvider: any OCRNamedEntityProviding = NaturalLanguageOCRNamedEntityProvider(),
        extractor: HotwordExtractor = HotwordExtractor(),
        ranker: HotwordRanker = HotwordRanker(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.screenshotProvider = screenshotProvider
        self.namedEntityProvider = namedEntityProvider
        self.extractor = extractor
        self.ranker = ranker
        self.now = now
    }

    func captureContext(for target: DictationTarget?) async -> OCRContextSnapshot? {
        guard let target,
              screenshotProvider.canCaptureScreen()
        else {
            AppLogger.dictation.debug("ContextBoost OCR skipped: screen capture unavailable app=\(target?.appName ?? "unknown") bundleID=\(target?.bundleID ?? "unknown")")
            return nil
        }
        guard let rawText = await screenshotProvider.visibleText(target: target),
              let text = ContextTextSanitizer.sanitize(rawText),
              !ContextPipeline.isNoise(text) else {
            AppLogger.dictation.debug("ContextBoost OCR skipped: no usable visible text app=\(target.appName ?? "unknown") bundleID=\(target.bundleID ?? "unknown")")
            return nil
        }

        return makeSnapshot(text: text, target: target)
    }

    fileprivate func makeSnapshot(text: String, target: DictationTarget) -> OCRContextSnapshot? {
        let capturedAt = now()
        let namedEntities = namedEntityProvider.namedEntities(in: text)
        let candidates = extractor.extract(
            from: text,
            namedEntities: namedEntities,
            now: capturedAt
        )
        let hotwords = ranker.rank(candidates)
        guard !hotwords.isEmpty else {
            AppLogger.dictation.debug("ContextBoost OCR produced no hotwords app=\(target.appName ?? "unknown") bundleID=\(target.bundleID ?? "unknown") ocrCharacters=\(text.count) candidates=\(candidates.count) namedEntities=\(namedEntities.count)")
            return nil
        }
        AppLogger.dictation.debug("ContextBoost OCR captured app=\(target.appName ?? "unknown") bundleID=\(target.bundleID ?? "unknown") ocrCharacters=\(text.count) candidates=\(candidates.count) namedEntities=\(namedEntities.count) topK=\(hotwords.map(\.text).joined(separator: ","))")

        return OCRContextSnapshot(
            bundleID: target.bundleID,
            appName: target.appName,
            windowTitle: target.windowTitle,
            capturedAt: capturedAt,
            hotwords: hotwords,
            ocrCharacterCount: text.count,
            candidateCount: candidates.count
        )
    }
}

extension CurrentWindowOCRContextProvider: ContextBoostOCRCaptureSessionProviding {
    func makeCaptureSession(for target: DictationTarget) -> (any ContextBoostOCRCaptureSession)? {
        guard screenshotProvider.canCaptureScreen() else { return nil }
        return SystemContextBoostOCRCaptureSession(
            target: target,
            snapshotBuilder: self
        )
    }
}

private final class SystemContextBoostOCRCaptureSession: ContextBoostOCRCaptureSession, @unchecked Sendable {
    private let target: DictationTarget
    private let snapshotBuilder: CurrentWindowOCRContextProvider
    private let screenshotProvider = SystemScreenshotProvider()
    private let lock = NSLock()
    private var cachedImage: CGImage?
    private var currentRequest: VNRecognizeTextRequest?

    init(target: DictationTarget, snapshotBuilder: CurrentWindowOCRContextProvider) {
        self.target = target
        self.snapshotBuilder = snapshotBuilder
    }

    func recognize(quality: ContextBoostOCRQuality) async -> ContextBoostOCRRecognitionOutcome {
        let image: CGImage
        if let cachedImage {
            image = cachedImage
        } else {
            guard let capturedImage = await screenshotProvider.captureWindowImage(target: target) else {
                return Task.isCancelled ? .cancelled : .noContext
            }
            cachedImage = capturedImage
            image = capturedImage
        }

        guard !Task.isCancelled else { return .cancelled }
        let request = SystemScreenshotProvider.makeRecognitionRequest(quality: quality)
        lock.withLock { currentRequest = request }
        defer {
            lock.withLock {
                if currentRequest === request {
                    currentRequest = nil
                }
            }
        }

        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        } catch {
            let nsError = error as NSError
            if nsError.domain == VNErrorDomain,
               nsError.code == VNErrorCode.requestCancelled.rawValue {
                return .cancelled
            }
            return .noContext
        }

        let candidates = request.results?.compactMap {
            $0.topCandidates(1).first?.string
        } ?? []
        guard let rawText = AccessibilityVisibleTextSummary.make(from: candidates),
              let text = ContextTextSanitizer.sanitize(rawText),
              !ContextPipeline.isNoise(text),
              let snapshot = snapshotBuilder.makeSnapshot(text: text, target: target) else {
            return .noContext
        }
        return .captured(snapshot)
    }

    func cancelCurrentRecognition() {
        lock.withLock { currentRequest?.cancel() }
    }
}

struct NaturalLanguageOCRNamedEntityProvider: OCRNamedEntityProviding {
    func namedEntities(in text: String) -> [NamedEntityCandidate] {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        let range = text.startIndex..<text.endIndex
        var candidates: [NamedEntityCandidate] = []

        tagger.enumerateTags(
            in: range,
            unit: .word,
            scheme: .nameType,
            options: [.omitWhitespace, .omitPunctuation, .joinNames]
        ) { tag, tokenRange in
            guard let tag,
                  let kind = NamedEntityKind(tag),
                  !tokenRange.isEmpty
            else {
                return true
            }
            let value = String(text[tokenRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return true }
            candidates.append(NamedEntityCandidate(text: value, kind: kind))
            return true
        }

        return candidates
    }
}

private extension NamedEntityKind {
    init?(_ tag: NLTag) {
        switch tag {
        case .personalName:
            self = .person
        case .placeName:
            self = .place
        case .organizationName:
            self = .organization
        default:
            return nil
        }
    }
}
