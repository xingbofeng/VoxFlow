import Foundation

/// Parses LLM structured correction responses, translating Light-Whisper's
/// `parse_structured_response` from Rust to Swift.
///
/// Supports multiple LLM output formats:
/// - Bare JSON object
/// - Array wrapper (first object)
/// - CDATA wrapper
/// - XML `<output>` wrapper
/// - JSON extraction from explanatory text
///
/// Parse failures fall back to raw text without blocking output (task 8.7).
struct StructuredCorrectionParser {
    private static let logger = AppLogger.dictation

    enum ParseError: Error, Equatable {
        case noJSONFound
        case invalidJSON
        case missingPolished
    }

    /// Parse result: either a successful structured output or a fallback.
    enum Result: Equatable {
        case success(StructuredCorrectionOutput)
        case fallback(rawText: String, reason: String)
    }

    /// Attempts to parse an LLM response into a structured correction output.
    /// Falls back to the raw text if parsing fails.
    static func parse(_ response: String) -> Result {
        guard !response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .fallback(rawText: response, reason: "empty_response")
        }

        // Strategy 1: Try direct JSON decode (bare JSON object)
        if let result = tryDecode(response) {
            return .success(result)
        }

        // Strategy 2: Try array wrapper (first object)
        if let result = tryParseArrayWrapper(response) {
            return .success(result)
        }

        // Strategy 3: Try CDATA wrapper
        if let result = tryParseCDATA(response) {
            return .success(result)
        }

        // Strategy 4: Try XML <output> wrapper
        if let result = tryParseXMLOutput(response) {
            return .success(result)
        }

        // Strategy 5: Extract JSON from explanatory text
        if let result = tryExtractJSONFromText(response) {
            return .success(result)
        }

        // All strategies failed — fall back to raw text
        logger.error("llm_structured_parse_failed responseLength=\(response.count)")
        return .fallback(rawText: response, reason: "llm_structured_parse_failed")
    }

    // MARK: - Strategy implementations

    /// Strategy 1: Direct JSON decode
    private static func tryDecode(_ text: String) -> StructuredCorrectionOutput? {
        guard let data = text.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8) else {
            return nil
        }
        return decodeAndValidate(data)
    }

    /// Strategy 2: Array wrapper — `[{"polished":...}]`
    private static func tryParseArrayWrapper(_ text: String) -> StructuredCorrectionOutput? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("[") else { return nil }

        guard let data = trimmed.data(using: .utf8),
              let array = try? JSONDecoder().decode([StructuredCorrectionOutput].self, from: data),
              let first = array.first else {
            return nil
        }
        return validate(first)
    }

    /// Strategy 3: CDATA wrapper — `<![CDATA[{"polished":...}]]>`
    private static func tryParseCDATA(_ text: String) -> StructuredCorrectionOutput? {
        guard text.contains("CDATA") else { return nil }

        // Extract content between CDATA[ and ]
        guard let cdataStart = text.range(of: "CDATA["),
              let cdataEnd = text.range(of: "]]>", range: cdataStart.upperBound..<text.endIndex) else {
            return nil
        }
        let content = String(text[cdataStart.upperBound..<cdataEnd.lowerBound])
        return tryDecode(content)
    }

    /// Strategy 4: XML <output> wrapper — `<output>{"polished":...}</output>`
    private static func tryParseXMLOutput(_ text: String) -> StructuredCorrectionOutput? {
        guard text.contains("<output>") else { return nil }

        guard let startTag = text.range(of: "<output>"),
              let endTag = text.range(of: "</output>", range: startTag.upperBound..<text.endIndex) else {
            return nil
        }
        let content = String(text[startTag.upperBound..<endTag.lowerBound])
        return tryDecode(content)
    }

    /// Strategy 5: Extract JSON object from explanatory text
    private static func tryExtractJSONFromText(_ text: String) -> StructuredCorrectionOutput? {
        // Find the first `{` and try to find the matching `}`
        guard let firstBrace = text.firstIndex(of: "{") else { return nil }

        // Try progressively larger substrings from the first brace
        let substring = String(text[firstBrace...])

        // Try to find a valid JSON object by scanning for closing braces
        var depth = 0
        var inString = false
        var escape = false
        var lastValidEnd: String.Index?

        for index in substring.indices {
            let char = substring[index]
            if escape {
                escape = false
                continue
            }
            if char == "\\" {
                escape = true
                continue
            }
            if char == "\"" {
                inString.toggle()
                continue
            }
            if inString { continue }
            if char == "{" {
                depth += 1
            } else if char == "}" {
                depth -= 1
                if depth == 0 {
                    lastValidEnd = index
                    let candidate = String(substring[substring.startIndex...index])
                    if let data = candidate.data(using: .utf8),
                       let result = decodeAndValidate(data) {
                        return result
                    }
                }
            }
        }

        // Try the last valid end as a final attempt
        if let end = lastValidEnd {
            let candidate = String(substring[substring.startIndex...end])
            if let data = candidate.data(using: .utf8),
               let result = decodeAndValidate(data) {
                return result
            }
        }

        return nil
    }

    // MARK: - Validation (tasks 8.8, 8.9)

    /// Decodes JSON and validates the output per spec.
    private static func decodeAndValidate(_ data: Data) -> StructuredCorrectionOutput? {
        guard let output = try? JSONDecoder().decode(StructuredCorrectionOutput.self, from: data) else {
            return nil
        }
        return validate(output)
    }

    /// Validates corrections and key_terms per spec:
    /// - corrections: only word/phrase-level, filter too long, empty, same value
    /// - key_terms: only reasonable proper nouns/terms, filter full sentences, common filler words, action commands
    private static func validate(_ output: StructuredCorrectionOutput) -> StructuredCorrectionOutput? {
        guard !output.polished.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let filteredCorrections = output.corrections.filter { correction in
            // Task 8.8: Filter empty, same value, too long
            let original = correction.original.trimmingCharacters(in: .whitespacesAndNewlines)
            let corrected = correction.corrected.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !original.isEmpty, !corrected.isEmpty else { return false }
            guard original != corrected else { return false }
            guard original.count <= 100, corrected.count <= 100 else { return false }
            return true
        }

        let filteredKeyTerms = output.keyTerms.filter { term in
            // Task 8.9: Filter full sentences, common filler words, action commands
            let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return false }
            // Too long = likely a sentence, not a term
            guard trimmed.count <= 50 else { return false }
            // Common filler words to exclude
            let fillers: Set<String> = ["嗯", "啊", "呃", "那个", "这个", "就是", "然后", "其实", "的话", "的话呢"]
            let normalized = trimmed.lowercased()
            for filler in fillers {
                if normalized == filler { return false }
            }
            // Action commands to exclude
            let actions: Set<String> = ["删除", "保存", "发送", "取消", "确认", "复制", "粘贴"]
            for action in actions {
                if normalized == action { return false }
            }
            return true
        }

        return StructuredCorrectionOutput(
            polished: output.polished,
            corrections: filteredCorrections,
            keyTerms: filteredKeyTerms
        )
    }
}
