import Foundation

/// Parses OpenAI-compatible SSE streams, emitting content deltas as they arrive.
///
/// Expected SSE format:
/// ```
/// data: {"id":"...","choices":[{"delta":{"content":"He"}}]}
/// data: {"id":"...","choices":[{"delta":{"content":"llo"}}]}
/// data: [DONE]
/// ```
enum SSEParser {
    /// Parses an SSE byte stream into an async stream of content delta strings.
    ///
    /// - Parameter byteStream: Raw byte stream from URLSession bytes(for:).
    /// - Returns: Async stream of content delta strings extracted from SSE events.
    static func parse<ByteStream: AsyncSequence & Sendable>(
        byteStream: ByteStream
    ) -> AsyncThrowingStream<String, Error> where ByteStream.Element == UInt8 {
        AsyncThrowingStream { continuation in
            let task = Task {
                var buffer = Data()
                var accumulatedText = ""

                for try await byte in byteStream {
                    buffer.append(byte)

                    // Process complete SSE events (delimited by a blank line).
                    while let eventRange = nextEventRange(in: buffer) {
                        let eventData = buffer[..<eventRange.lowerBound]
                        buffer.removeSubrange(..<eventRange.upperBound)

                        guard let event = String(data: eventData, encoding: .utf8) else {
                            continue
                        }
                        if processEvent(event, accumulatedText: &accumulatedText, continuation: continuation) {
                            return
                        }
                    }
                }

                // Process any remaining data in buffer when stream ends without [DONE]
                if !buffer.isEmpty {
                    if let event = String(data: buffer, encoding: .utf8),
                       processEvent(event, accumulatedText: &accumulatedText, continuation: continuation) {
                        return
                    }
                }

                continuation.finish()
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    private static func nextEventRange(in buffer: Data) -> Range<Data.Index>? {
        let lfDelimiter = Data([0x0A, 0x0A])
        let crlfDelimiter = Data([0x0D, 0x0A, 0x0D, 0x0A])

        let lfRange = buffer.range(of: lfDelimiter)
        let crlfRange = buffer.range(of: crlfDelimiter)

        switch (lfRange, crlfRange) {
        case let (lf?, crlf?):
            return lf.lowerBound < crlf.lowerBound ? lf : crlf
        case let (lf?, nil):
            return lf
        case let (nil, crlf?):
            return crlf
        case (nil, nil):
            return nil
        }
    }

    private static func processEvent(
        _ event: String,
        accumulatedText: inout String,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) -> Bool {
        for line in event.split(separator: "\n", omittingEmptySubsequences: true) {
            guard line.hasPrefix("data: ") else { continue }
            let dataString = line.dropFirst(6).trimmingCharacters(in: .whitespacesAndNewlines)

            if dataString == "[DONE]" {
                continuation.finish()
                return true
            }

            guard let data = dataString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let delta = firstChoice["delta"] as? [String: Any],
                  let content = delta["content"] as? String,
                  !content.isEmpty else {
                // Skip empty deltas (role-only, metadata-only chunks)
                continue
            }

            accumulatedText += content
            continuation.yield(accumulatedText)
        }
        return false
    }
}
