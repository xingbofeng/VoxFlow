import Testing
@testable import VoxFlowVoiceCorrection

@Suite("VoxFlowVoiceCorrection package")
struct VoxFlowVoiceCorrectionPackageTests {
    @Test("exposes the package identity")
    func exposesPackageIdentity() {
        #expect(VoxFlowVoiceCorrection.packageName == "VoxFlowVoiceCorrection")
    }
}
