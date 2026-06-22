import CoreGraphics
import Foundation
import Vision

final class VisionTextOCRRecognizer: TextOCRRecognizing {
    func recognizeText(in image: CGImage) async throws -> String {
        AppLogger.general.debug("Vision OCR recognizeText start size=\(image.width)x\(image.height)")
        let lines = try await recognizeTextLines(in: image)
        let text = lines
            .map(\.text)
            .joined(separator: "\n")
        AppLogger.general.debug("Vision OCR recognizeText completed lines=\(lines.count), textLength=\(text.count)")
        return text
    }

    func recognizeTextLines(in image: CGImage) async throws -> [OCRLine] {
        AppLogger.general.debug("Vision OCR line recognition start size=\(image.width)x\(image.height)")
        try Task.checkCancellation()
        do {
            let lines: [OCRLine] = try await Task.detached(priority: .userInitiated) { () throws -> [OCRLine] in
                try Task.checkCancellation()
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
                try Task.checkCancellation()

                let observations = (request.results ?? []).map { $0 }
                let imageWidth = CGFloat(image.width)
                let imageHeight = CGFloat(image.height)

                // Vision 返回 normalized bottom-left 坐标；翻转到 image top-left points。
                // y_top = (1 - bbox.minY) * imageHeight - bbox.height * imageHeight
                //      = (1 - bbox.maxY) * imageHeight
                return observations.compactMap { observation in
                    guard let text = observation.topCandidates(1).first?.string else {
                        return nil
                    }
                    let bbox = observation.boundingBox
                    let x = bbox.minX * imageWidth
                    let y = (1 - bbox.maxY) * imageHeight
                    let width = bbox.width * imageWidth
                    let height = bbox.height * imageHeight
                    return OCRLine(
                        text: text,
                        boundingBox: CGRect(x: x, y: y, width: width, height: height)
                    )
                }
            }.value
            AppLogger.general.debug("Vision OCR line recognition completed lines=\(lines.count)")
            return lines
        } catch {
            AppLogger.general.warning("Vision OCR failed: \(error.localizedDescription)")
            throw error
        }
    }
}
