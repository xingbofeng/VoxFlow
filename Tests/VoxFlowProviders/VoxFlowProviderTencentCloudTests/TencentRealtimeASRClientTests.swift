import Foundation
import VoxFlowProviderTencentCloud
import XCTest

final class TencentRealtimeASRClientTests: XCTestCase {
    func testRealtimeURLContainsRequiredQueryAndRedactsSecretKey() throws {
        let signer = TencentRealtimeASRURLSigner(
            appID: "1259220000",
            secretID: "AKIDEXAMPLE",
            secretKey: "SECRETEXAMPLE",
            timestamp: 1_673_408_372,
            expired: 1_673_494_772,
            nonce: 1_673_408_372,
            voiceID: "c64385ee-3e5c-4fc5-bbfd-7c71addb35b0",
            engineModelType: "16k_zh",
            voiceFormat: 1,
            needVAD: 1
        )

        let signedURL = try signer.signedURL()
        let components = try XCTUnwrap(URLComponents(url: signedURL, resolvingAgainstBaseURL: false))
        let items: [URLQueryItem] = components.queryItems ?? []
        let queryItems = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(components.scheme, "wss")
        XCTAssertEqual(components.host, "asr.cloud.tencent.com")
        XCTAssertEqual(components.path, "/asr/v2/1259220000")
        XCTAssertEqual(queryItems["secretid"], "AKIDEXAMPLE")
        XCTAssertEqual(queryItems["engine_model_type"], "16k_zh")
        XCTAssertEqual(queryItems["voice_format"], "1")
        XCTAssertNotNil(queryItems["signature"])
        XCTAssertFalse(signer.redactedDescription.contains("SECRETEXAMPLE"))
        XCTAssertFalse(signedURL.absoluteString.contains("SECRETEXAMPLE"))
    }

    func testRealtimeURLPercentEncodesBase64SignatureReservedCharacters() throws {
        let signer = TencentRealtimeASRURLSigner(
            appID: "1259220000",
            secretID: "AKIDEXAMPLE",
            secretKey: "SECRETEXAMPLE4",
            timestamp: 1_673_408_372,
            expired: 1_673_494_772,
            nonce: 1_673_408_372,
            voiceID: "c64385ee-3e5c-4fc5-bbfd-7c71addb35b0",
            engineModelType: "16k_zh",
            voiceFormat: 1,
            needVAD: 1
        )

        let signedURL = try signer.signedURL()
        let query = try XCTUnwrap(URLComponents(url: signedURL, resolvingAgainstBaseURL: false)?.percentEncodedQuery)

        XCTAssertTrue(query.contains("signature=XK3pBX9JULp%2BNfBx2mHr94h1y%2Bw%3D"))
        XCTAssertFalse(query.contains("+"))
    }

    func testParsesPartialStableAndFinalMessages() throws {
        let partial = try TencentRealtimeASRMessage.decode(
            Data(#"{"code":0,"message":"success","voice_id":"v","result":{"slice_type":1,"index":0,"voice_text_str":"实时"}}"#.utf8)
        )
        let stable = try TencentRealtimeASRMessage.decode(
            Data(#"{"code":0,"message":"success","voice_id":"v","result":{"slice_type":2,"index":0,"voice_text_str":"实时语音识别"}}"#.utf8)
        )
        let final = try TencentRealtimeASRMessage.decode(
            Data(#"{"code":0,"message":"success","voice_id":"v","final":1}"#.utf8)
        )

        XCTAssertEqual(partial.transcript, "实时")
        XCTAssertFalse(partial.isStable)
        XCTAssertFalse(partial.isFinal)
        XCTAssertEqual(stable.transcript, "实时语音识别")
        XCTAssertTrue(stable.isStable)
        XCTAssertFalse(stable.isFinal)
        XCTAssertTrue(final.isFinal)
    }
}
