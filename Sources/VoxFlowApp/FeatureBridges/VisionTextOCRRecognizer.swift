import CoreGraphics
import Foundation
import Vision

@MainActor
final class VisionTextOCRRecognizer: TextOCRRecognizing {
    func recognizeText(in image: CGImage) async throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = [
            "zh-Hans",
            "zh-Hant",
            "en-US",
            "ja-JP",
            "ko-KR",
        ]

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        let observations = request.results ?? []
        return observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }
}
