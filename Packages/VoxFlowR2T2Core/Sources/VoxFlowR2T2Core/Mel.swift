import Accelerate
import Foundation

/// transformers' `WhisperFeatureExtractor` (n_fft 400, hop 160, 128 Slaney mel bins, 16 kHz),
/// reproduced in DOUBLE precision on Accelerate.
///
/// The Python-MLX rung this port is gated against feeds features from numpy: float64 STFT whose
/// bins are stored as complex64, |X|² in float64, the mel dot product and log10 in float64, the
/// `max(x, x.max() - 8)` clamp, `(x + 4) / 4`, then a cast to float32. Reproducing that pipeline
/// step for step (including the complex64 rounding of the bins) is what makes the encoder gate a
/// question about the encoder rather than about FFT libraries. A float32 MLX front-end differs at
/// ~1e-6 and flips greedy argmax on near-ties, which reads as a port defect (the bf16 trap).
///
/// Framing follows `audio_utils.spectrogram` with `center=True, pad_mode="reflect"`: the waveform
/// is reflect-padded by n_fft/2 on both sides, `1 + (len + 2·pad − n_fft) / hop` frames are
/// taken, and Whisper then DROPS the last frame (`log_spec[:, :-1]`).
public struct WhisperLogMel: Sendable {
    public let nFFT: Int
    public let hop: Int
    public let nMels: Int
    public let sampleRate: Int
    public var nBins: Int { nFFT / 2 + 1 }

    private let window: [Double]      // periodic Hann, nFFT
    private let dft: [Double]         // [nFFT × 2·nBins]: cos block then −sin block, row = sample index
    private let filters: [Double]     // [nBins × nMels], frequency-major

    public init(nFFT: Int = 400, hop: Int = 160, nMels: Int = 128, sampleRate: Int = 16000, fMax: Double = 8000) {
        self.nFFT = nFFT
        self.hop = hop
        self.nMels = nMels
        self.sampleRate = sampleRate
        let bins = nFFT / 2 + 1
        // window_function(400, "hann", periodic=True) == np.hanning(401)[:-1]
        window = (0 ..< nFFT).map { 0.5 - 0.5 * cos(2.0 * Double.pi * Double($0) / Double(nFFT)) }
        var d = [Double](repeating: 0, count: nFFT * 2 * bins)
        for n in 0 ..< nFFT {
            for k in 0 ..< bins {
                let a = 2.0 * Double.pi * Double(k) * Double(n) / Double(nFFT)
                d[n * 2 * bins + k] = cos(a)
                d[n * 2 * bins + bins + k] = -sin(a)
            }
        }
        dft = d
        filters = WhisperLogMel.slaneyFilterBank(bins: bins, nMels: nMels, sampleRate: sampleRate, fMin: 0, fMax: fMax)
    }

    /// `mel_filter_bank(num_frequency_bins, num_mel_filters, 0, 8000, sr, norm="slaney", mel_scale="slaney")`.
    static func slaneyFilterBank(bins: Int, nMels: Int, sampleRate: Int, fMin: Double, fMax: Double) -> [Double] {
        func hzToMel(_ f: Double) -> Double {
            let minLogHz = 1000.0, minLogMel = 15.0, logstep = 27.0 / log(6.4)
            return f >= minLogHz ? minLogMel + log(f / minLogHz) * logstep : 3.0 * f / 200.0
        }
        func melToHz(_ m: Double) -> Double {
            let minLogHz = 1000.0, minLogMel = 15.0, logstep = log(6.4) / 27.0
            return m >= minLogMel ? minLogHz * exp(logstep * (m - minLogMel)) : 200.0 * m / 3.0
        }
        // np.linspace: start + i*step, last element pinned to stop.
        func linspace(_ a: Double, _ b: Double, _ n: Int) -> [Double] {
            let step = (b - a) / Double(n - 1)
            var out = (0 ..< n).map { a + Double($0) * step }
            out[n - 1] = b
            return out
        }
        let melFreqs = linspace(hzToMel(fMin), hzToMel(fMax), nMels + 2)
        let filterFreqs = melFreqs.map(melToHz)
        let fftFreqs = linspace(0, Double(sampleRate / 2), bins)
        var fb = [Double](repeating: 0, count: bins * nMels)
        for i in 0 ..< bins {
            for j in 0 ..< nMels {
                let down = -(filterFreqs[j] - fftFreqs[i]) / (filterFreqs[j + 1] - filterFreqs[j])
                let up = (filterFreqs[j + 2] - fftFreqs[i]) / (filterFreqs[j + 2] - filterFreqs[j + 1])
                let enorm = 2.0 / (filterFreqs[j + 2] - filterFreqs[j])
                fb[i * nMels + j] = max(0.0, min(down, up)) * enorm
            }
        }
        return fb
    }

    /// Whisper log-mel features for a mono 16 kHz clip: `[frames, nMels]`, frame-major, float32.
    /// `samples.count` must exceed n_fft/2 (the reflect pad); the streaming loop pads short tails.
    public func features(_ samples: [Float]) -> (frames: Int, data: [Float]) {
        let pad = nFFT / 2
        precondition(samples.count > pad, "clip shorter than the reflect pad")
        let n = samples.count
        // np.pad(mode="reflect"): left = x[pad], x[pad-1], …, x[1]; right = x[n-2], …, x[n-1-pad]
        var padded = [Double](repeating: 0, count: n + 2 * pad)
        for i in 0 ..< pad { padded[i] = Double(samples[pad - i]) }
        for i in 0 ..< n { padded[pad + i] = Double(samples[i]) }
        for i in 0 ..< pad { padded[pad + n + i] = Double(samples[n - 2 - i]) }
        let framesAll = 1 + (padded.count - nFFT) / hop
        let bins = nBins
        // Windowed frames [framesAll × nFFT]
        var frameMatrix = [Double](repeating: 0, count: framesAll * nFFT)
        for t in 0 ..< framesAll {
            let base = t * hop
            for i in 0 ..< nFFT { frameMatrix[t * nFFT + i] = padded[base + i] * window[i] }
        }
        // rfft as one dgemm: [framesAll × nFFT] · [nFFT × 2·bins]
        var spec = [Double](repeating: 0, count: framesAll * 2 * bins)
        cblas_dgemm(CblasRowMajor, CblasNoTrans, CblasNoTrans, Int32(framesAll), Int32(2 * bins), Int32(nFFT),
                    1.0, frameMatrix, Int32(nFFT), dft, Int32(2 * bins), 0.0, &spec, Int32(2 * bins))
        // complex64 storage → |X|² in float64
        var power = [Double](repeating: 0, count: framesAll * bins)
        for t in 0 ..< framesAll {
            for k in 0 ..< bins {
                let re = Double(Float(spec[t * 2 * bins + k]))
                let im = Double(Float(spec[t * 2 * bins + bins + k]))
                power[t * bins + k] = re * re + im * im
            }
        }
        // mel: [framesAll × bins] · [bins × nMels]
        var mel = [Double](repeating: 0, count: framesAll * nMels)
        cblas_dgemm(CblasRowMajor, CblasNoTrans, CblasNoTrans, Int32(framesAll), Int32(nMels), Int32(bins),
                    1.0, power, Int32(bins), filters, Int32(nMels), 0.0, &mel, Int32(nMels))
        let frames = framesAll - 1   // Whisper drops the last frame
        let count = frames * nMels
        var logMel = [Double](repeating: 0, count: count)
        var maxVal = -Double.infinity
        for i in 0 ..< count {
            let v = log10(max(mel[i], 1e-10))
            logMel[i] = v
            if v > maxVal { maxVal = v }
        }
        let floor = maxVal - 8.0
        var out = [Float](repeating: 0, count: count)
        for i in 0 ..< count { out[i] = Float((max(logMel[i], floor) + 4.0) / 4.0) }
        return (frames, out)
    }

    /// Frames a clip of `samples` produces (before/after the dropped frame is the caller's concern).
    public func frameCount(samples: Int) -> Int { samples / hop }
}

/// `_get_feat_extract_output_lengths` — audio tokens produced from `frames` mel frames: 13 per
/// full 100-frame conv chunk plus the 3×(k−1)/2+1 chain on the remainder. Python floor division.
public func qwen3ASRAudioTokenCount(frames: Int, chunkFrames: Int = 100) -> Int {
    func floorDiv(_ a: Int, _ b: Int) -> Int { a >= 0 ? a / b : -((-a + b - 1) / b) }
    let leave = frames % chunkFrames
    let feat = floorDiv(leave - 1, 2) + 1
    let out = floorDiv(floorDiv(feat - 1, 2) + 1 - 1, 2) + 1
    return out + (frames / chunkFrames) * 13
}
