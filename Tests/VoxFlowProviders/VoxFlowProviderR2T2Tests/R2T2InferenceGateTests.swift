import Foundation
import XCTest
@testable import VoxFlowProviderR2T2

/// 同一个模型目录下的多个会话共享同一份已加载权重，推理必须串行 —— 否则两次 MLX 前向会交叠，
/// 而 KV cache 是按 stream 分配的，交叠时共享的是模型的惰性求值图。
final class R2T2InferenceGateTests: XCTestCase {
    func testConcurrentRunsNeverOverlap() {
        let gate = R2T2InferenceGate()
        let probe = InferenceConcurrencyProbe()

        DispatchQueue.concurrentPerform(iterations: 8) { _ in
            gate.run { probe.runInference() }
        }

        XCTAssertEqual(probe.maxConcurrentInferences, 1, "同一模型的推理不得并发")
        XCTAssertEqual(probe.totalInferences, 8, "gate 必须让每一次调用都执行")
    }

    func testRunReturnsTheBodyResult() {
        let gate = R2T2InferenceGate()

        XCTAssertEqual(gate.run { 41 + 1 }, 42)
    }
}

private final class InferenceConcurrencyProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var inFlight = 0
    private var maxInFlight = 0
    private var total = 0

    var maxConcurrentInferences: Int { lock.withLock { maxInFlight } }
    var totalInferences: Int { lock.withLock { total } }

    /// 模拟一次推理：进入、停留一小段时间、离开。停留是为了让交叠真的有机会发生。
    func runInference() {
        lock.withLock {
            inFlight += 1
            total += 1
            maxInFlight = max(maxInFlight, inFlight)
        }
        usleep(5_000)
        lock.withLock { inFlight -= 1 }
    }
}
