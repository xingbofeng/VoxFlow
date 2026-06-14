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
                var buffer = ""
                var accumulatedText = ""

                for try await byte in byteStream {
                    buffer.append(Character(UnicodeScalar(byte)))

                    // Process complete SSE events (delimited by \n\n)
                    while let eventEnd = buffer.range(of: "\n\n") {
                        let event = String(buffer[buffer.startIndex..<eventEnd.lowerBound])
                        buffer = String(buffer[eventEnd.upperBound..<buffer.endIndex])

                        for line in event.split(separator: "\n", omittingEmptySubsequences: true) {
                            guard line.hasPrefix("data: ") else { continue }
                            let dataString = line.dropFirst(6).trimmingCharacters(in: .whitespaces)

                            if dataString == "[DONE]" {
                                continuation.finish()
                                return
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
                    }
                }

                // Process any remaining data in buffer when stream ends without [DONE]
                if !buffer.isEmpty {
                    let remainingLines = buffer.split(separator: "\n", omittingEmptySubsequences: true)
                    for line in remainingLines {
                        guard line.hasPrefix("data: ") else { continue }
                        let dataString = line.dropFirst(6).trimmingCharacters(in: .whitespaces)

                        if dataString == "[DONE]" {
                            continuation.finish()
                            return
                        }

                        guard let data = dataString.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let choices = json["choices"] as? [[String: Any]],
                              let firstChoice = choices.first,
                              let delta = firstChoice["delta"] as? [String: Any],
                              let content = delta["content"] as? String,
                              !content.isEmpty else {
                            continue
                        }

                        accumulatedText += content
                        continuation.yield(accumulatedText)
                    }
                }

                continuation.finish()
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

}
