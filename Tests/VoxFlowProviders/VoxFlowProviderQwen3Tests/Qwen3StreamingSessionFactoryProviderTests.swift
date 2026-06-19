@testable import VoxFlowProviderQwen3
import XCTest

final class Qwen3StreamingSessionFactoryProviderTests: XCTestCase {
    func testVariantFactoryRoutesBothQwen3SizesThroughSpeechSwift() {
        let qwen06Factory = Qwen3StreamingSessionFactoryProvider.factory(for: .qwen06SpeechSwift4Bit)
        let speechSwiftFactory = Qwen3StreamingSessionFactoryProvider.factory(for: .qwen17SpeechSwift8Bit)

        XCTAssertTrue(qwen06Factory is SpeechSwiftQwen3StreamingSessionFactory)
        XCTAssertTrue(speechSwiftFactory is SpeechSwiftQwen3StreamingSessionFactory)
    }
}
