import XCTest
import VoxFlowASRCore

final class ASRTimeoutPolicyTests: XCTestCase {
    func testTimeoutPolicySeparatesRecognitionStages() {
        let policy = ASRTimeoutPolicy(
            preparationTimeout: .seconds(30),
            firstPartialTimeout: .seconds(5),
            streamStallTimeout: .seconds(8),
            finalBaseTimeout: .seconds(15),
            finalPerAudioSecondTimeout: .seconds(1),
            workerHeartbeatTimeout: .seconds(3),
            initialModelCompilationTimeout: .seconds(600)
        )

        XCTAssertEqual(policy.timeout(for: .preparation), .seconds(30))
        XCTAssertEqual(policy.timeout(for: .firstPartial), .seconds(5))
        XCTAssertEqual(policy.timeout(for: .streamStall), .seconds(8))
        XCTAssertEqual(policy.timeout(for: .final(audioDuration: .seconds(20))), .seconds(35))
        XCTAssertEqual(policy.timeout(for: .workerHeartbeat), .seconds(3))
        XCTAssertEqual(policy.timeout(for: .initialModelCompilation), .seconds(600))
    }

    func testProviderDescriptorCanCarryCustomTimeoutPolicy() {
        let timeoutPolicy = ASRTimeoutPolicy(
            preparationTimeout: .seconds(45),
            firstPartialTimeout: .seconds(4),
            streamStallTimeout: .seconds(7),
            finalBaseTimeout: .seconds(12),
            finalPerAudioSecondTimeout: .milliseconds(500),
            workerHeartbeatTimeout: .seconds(2),
            initialModelCompilationTimeout: .seconds(900)
        )
        let descriptor = ASRProviderDescriptor(
            id: ASRProviderID(rawValue: "provider"),
            displayName: "Provider",
            modelInstallationState: .ready,
            supportedLanguages: [ASRLanguageCapability(bcp47Tag: "en")],
            streamingSemantics: .nativeStreaming,
            timeoutPolicy: timeoutPolicy
        )

        XCTAssertEqual(descriptor.timeoutPolicy, timeoutPolicy)
    }
}
