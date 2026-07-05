import Foundation
import VoxFlowAudio

/// PCM16 编码与采样率校验工具，跨平台共享。
public enum PCM16Encoding {
    /// 将 Float 样本编码为 little-endian Int16 PCM 数据。
    public static func pcm16Data(samples: ContiguousArray<Float>) -> Data {
        var data = Data(capacity: samples.count * MemoryLayout<Int16>.size)
        for sample in samples {
            let clamped = min(1, max(-1, sample))
            var value = Int16(clamped * Float(Int16.max)).littleEndian
            withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
        }
        return data
    }
}
