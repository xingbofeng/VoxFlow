import Foundation
import VoxFlowPromptKit

struct TextTransformChunk: Equatable, Sendable {
    let index: Int
    let text: String
    let sourceRange: Range<Int>
}

enum TextTransformEvent: Equatable, Sendable {
    case started(totalUnits: Int?)
    case partialText(String)
    case unitCompleted(index: Int, text: String)
    case completed(String)
    case cancelled(partialText: String)
    case failed(message: String, partialText: String)
}

struct LineTransformEvent: Equatable, Sendable {
    let completedLines: [Int: String]
    let totalLineCount: Int
    let isFinal: Bool
}

enum TextTransformOperation: Equatable, Sendable {
    case translation
    case summary
}

protocol TextTransformAvailabilityMessaging: Sendable {
    func unavailableMessage(for operation: TextTransformOperation) -> String
}

struct TextTransformRequest: Equatable, Sendable {
    let text: String
    let operation: TextTransformOperation
    let systemPrompt: String?
    let temperature: Double

    init(
        text: String,
        operation: TextTransformOperation,
        systemPrompt: String? = nil,
        temperature: Double = 0.2
    ) {
        self.text = text
        self.operation = operation
        self.systemPrompt = systemPrompt
        self.temperature = temperature
    }
}

enum TextTransformPromptBuilder {
    private static let renderer = PromptRenderer()

    static var translationSystemPrompt: String {
        renderer.render(TextTransformPromptCatalog.translation).renderedText
    }

    static var summarySystemPrompt: String {
        renderer.render(TextTransformPromptCatalog.summary).renderedText
    }

    static func refinementRequest(for request: TextTransformRequest) -> TextRefinementRequest {
        let renderResult = renderResult(for: request.operation)
        let systemPrompt = request.systemPrompt ?? renderResult.renderedText
        return TextRefinementRequest(
            text: request.text,
            systemPrompt: systemPrompt,
            model: nil,
            temperature: request.temperature,
            purpose: .directTask,
            promptMetadata: request.systemPrompt == nil
                ? PromptTraceMetadata.from(result: renderResult)
                : nil
        )
    }

    private static func renderResult(for operation: TextTransformOperation) -> PromptRenderResult {
        switch operation {
        case .translation:
            return renderer.render(TextTransformPromptCatalog.translation)
        case .summary:
            return renderer.render(TextTransformPromptCatalog.summary)
        }
    }
}

final class TextTransformService {
    private let refiner: any PromptAwareTextRefining
    private let maxCharactersPerChunk: Int

    init(
        refiner: any PromptAwareTextRefining,
        maxCharactersPerChunk: Int = 4_000
    ) {
        self.refiner = refiner
        self.maxCharactersPerChunk = maxCharactersPerChunk
    }

    func events(for request: TextTransformRequest) -> AsyncStream<TextTransformEvent> {
        let refiner = self.refiner
        let maxCharactersPerChunk = self.maxCharactersPerChunk
        return AsyncStream<TextTransformEvent> { continuation in
            let task = Task {
                guard refiner.isEnabled, refiner.isConfigured else {
                    let message = (refiner as? any TextTransformAvailabilityMessaging)?
                        .unavailableMessage(for: request.operation) ?? L10n.localize(
                            "llm.text_transform.unavailable_message",
                            comment: "Text transform unavailable message"
                        )
                    continuation.yield(.failed(message: message, partialText: ""))
                    continuation.finish()
                    return
                }

                var latestText = ""
                do {
                    if let streamingRefiner = refiner as? any StreamingPromptAwareTextRefining {
                        continuation.yield(.started(totalUnits: nil))
                        let refinementRequest = TextTransformPromptBuilder.refinementRequest(for: request)
                        for try await snapshot in streamingRefiner.refineStream(refinementRequest) {
                            latestText = snapshot
                            continuation.yield(.partialText(snapshot))
                        }
                    } else {
                        let chunks = TextTransformChunker.chunks(
                            for: request.text,
                            maxCharactersPerChunk: maxCharactersPerChunk
                        )
                        continuation.yield(.started(totalUnits: chunks.count))
                        var completedChunks: [String] = []
                        for chunk in chunks {
                            try Task.checkCancellation()
                            let chunkRequest = TextTransformRequest(
                                text: chunk.text,
                                operation: request.operation
                            )
                            let refinementRequest = TextTransformPromptBuilder.refinementRequest(for: chunkRequest)
                            let transformed = try await refiner.refine(refinementRequest)
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            completedChunks.append(transformed)
                            latestText = completedChunks.joined(separator: "\n\n")
                            continuation.yield(.unitCompleted(index: chunk.index, text: transformed))
                            continuation.yield(.partialText(latestText))
                        }
                    }
                    continuation.yield(.completed(latestText))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.yield(.cancelled(partialText: latestText))
                    continuation.finish()
                } catch {
                    continuation.yield(.failed(message: error.localizedDescription, partialText: latestText))
                    continuation.finish()
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
}

enum TextTransformChunker {
    static func chunks(
        for text: String,
        maxCharactersPerChunk: Int
    ) -> [TextTransformChunk] {
        guard !text.isEmpty else {
            return [TextTransformChunk(index: 0, text: "", sourceRange: 0..<0)]
        }

        let units = paragraphUnits(in: text)
            .flatMap { splitOversizedUnit($0, maxCharactersPerChunk: maxCharactersPerChunk) }
        guard !units.isEmpty else {
            return [TextTransformChunk(index: 0, text: text, sourceRange: 0..<text.count)]
        }

        var chunks: [TextTransformChunk] = []
        var currentText = ""
        var currentStart: Int?
        var currentEnd = 0

        func flushCurrent() {
            guard let start = currentStart, !currentText.isEmpty else { return }
            chunks.append(TextTransformChunk(
                index: chunks.count,
                text: currentText,
                sourceRange: start..<currentEnd
            ))
            currentText = ""
            currentStart = nil
            currentEnd = 0
        }

        for unit in units {
            let candidate = currentText.isEmpty ? unit.text : "\(currentText)\n\n\(unit.text)"
            if !currentText.isEmpty,
               candidate.count > maxCharactersPerChunk {
                flushCurrent()
            }

            if currentText.isEmpty {
                currentText = unit.text
                currentStart = unit.range.lowerBound
                currentEnd = unit.range.upperBound
            } else {
                currentText = "\(currentText)\n\n\(unit.text)"
                currentEnd = unit.range.upperBound
            }
        }

        flushCurrent()
        return chunks
    }

    private static func paragraphUnits(in text: String) -> [(text: String, range: Range<Int>)] {
        var units: [(text: String, range: Range<Int>)] = []
        var searchStart = text.startIndex

        for part in text.components(separatedBy: "\n\n") {
            guard let range = text.range(of: part, range: searchStart..<text.endIndex) else {
                continue
            }
            if !part.isEmpty {
                let lower = text.distance(from: text.startIndex, to: range.lowerBound)
                let upper = text.distance(from: text.startIndex, to: range.upperBound)
                units.append((text: part, range: lower..<upper))
            }
            searchStart = range.upperBound
        }

        return units
    }

    private static func splitOversizedUnit(
        _ unit: (text: String, range: Range<Int>),
        maxCharactersPerChunk: Int
    ) -> [(text: String, range: Range<Int>)] {
        guard maxCharactersPerChunk > 0,
              unit.text.count > maxCharactersPerChunk,
              !isMarkdownCodeFence(unit.text) else {
            return [unit]
        }

        var pieces: [(text: String, range: Range<Int>)] = []
        var startIndex = unit.text.startIndex
        var sourceOffset = unit.range.lowerBound

        while startIndex < unit.text.endIndex {
            let endIndex = unit.text.index(
                startIndex,
                offsetBy: maxCharactersPerChunk,
                limitedBy: unit.text.endIndex
            ) ?? unit.text.endIndex
            let piece = String(unit.text[startIndex..<endIndex])
            pieces.append((
                text: piece,
                range: sourceOffset..<(sourceOffset + piece.count)
            ))
            sourceOffset += piece.count
            startIndex = endIndex
        }

        return pieces
    }

    private static func isMarkdownCodeFence(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return false }
        return trimmed.dropFirst(3).contains("```")
    }
}
