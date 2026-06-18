import Accelerate
@preconcurrency import AVFoundation

final class AudioPreprocessor {
    // MARK: - Resample

    /// Resamples an AVAudioPCMBuffer of any format to 16 kHz mono float samples.
    static func resampleTo16kHz(_ buffer: AVAudioPCMBuffer) -> [Float]? {
        guard buffer.frameLength > 0 else { return nil }
        let sourceFormat = buffer.format

        let targetSampleRate: Double = 16000
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else { return nil }

        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            return nil
        }

        let targetFrameCapacity = AVAudioFrameCount(
            Double(buffer.frameLength) * targetSampleRate / sourceFormat.sampleRate + 128
        )
        guard let targetBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: targetFrameCapacity
        ) else { return nil }

        // Track whether the input buffer has already been provided.
        // Without this guard AVAudioConverter may call the block again after
        // exhausting the buffer, re-reading the same samples and producing
        // duplicated/garbled audio that downstream ASR engines cannot decode.
        nonisolated(unsafe) var inputProvided = false
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if inputProvided {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputProvided = true
            outStatus.pointee = .haveData
            return buffer
        }

        var error: NSError?
        converter.convert(to: targetBuffer, error: &error, withInputFrom: inputBlock)

        if let error = error {
            AppLogger.audio.error("AudioPreprocessor: resample error: \(error)")
            return nil
        }

        let frameCount = Int(targetBuffer.frameLength)
        guard let channelData = targetBuffer.floatChannelData,
              frameCount > 0 else { return nil }

        return Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
    }

    // MARK: - Fbank

    /// Extracts log Mel filterbank features from 16kHz mono audio samples.
    /// - Parameters:
    ///   - samples: 16kHz mono PCM samples
    ///   - sampleRate: sample rate in Hz (default 16000)
    ///   - nMel: number of Mel filterbank bands (default 80)
    /// - Returns: 2D array of shape [nFrames × nMel]
    static func extractFbank(
        _ samples: [Float],
        sampleRate: Int = 16000,
        nMel: Int = 80
    ) -> [[Float]] {
        guard !samples.isEmpty else { return [] }

        let frameLength = 400   // 25ms at 16kHz
        let frameShift = 160    // 10ms at 16kHz
        let nFft = 512

        let frames = frameSignal(samples, frameLength: frameLength, frameShift: frameShift)

        // Precompute Hann window
        var hannWindow = [Float](repeating: 0, count: frameLength)
        vDSP_hann_window(&hannWindow, vDSP_Length(frameLength), Int32(vDSP_HANN_NORM))

        // FFT setup
        let log2n = vDSP_Length(log2(Float(nFft)))
        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return []
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        // Mel filterbank
        let melFilters = createMelFilterbank(
            nFft: nFft,
            sampleRate: Float(sampleRate),
            nMel: nMel
        )

        // Allocate split-complex buffers once for efficiency
        let halfNfft = nFft / 2
        let realp = UnsafeMutablePointer<Float>.allocate(capacity: halfNfft)
        let imagp = UnsafeMutablePointer<Float>.allocate(capacity: halfNfft)
        defer { realp.deallocate(); imagp.deallocate() }

        let nBins = nFft / 2 + 1
        var result: [[Float]] = []

        for var frame in frames {
            // Apply Hann window
            vDSP_vmul(frame, 1, hannWindow, 1, &frame, 1, vDSP_Length(frameLength))

            // Pad to nFft
            let padded = frame + [Float](repeating: 0, count: nFft - frameLength)

            // Pack interleaved real signal into DSPSplitComplex via vDSP_ctoz
            padded.withUnsafeBufferPointer { bufPtr in
                bufPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfNfft) { complexPtr in
                    var split = DSPSplitComplex(realp: realp, imagp: imagp)
                    vDSP_ctoz(complexPtr, 2, &split, 1, vDSP_Length(halfNfft))
                }
            }

            // Forward FFT in-place
            var split = DSPSplitComplex(realp: realp, imagp: imagp)
            vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))

            // Power spectrum = |fft|^2
            var powerSpec = [Float](repeating: 0, count: nBins)
            vDSP_zvabs(&split, 1, &powerSpec, 1, vDSP_Length(halfNfft))
            // Square
            vDSP_vsq(powerSpec, 1, &powerSpec, 1, vDSP_Length(nBins))
            // Normalize by FFT length
            let scale = 1.0 / Float(nFft * nFft)
            vDSP_vsmul(powerSpec, 1, [scale], &powerSpec, 1, vDSP_Length(nBins))

            // Apply Mel filterbank
            var melFrame = [Float](repeating: 0, count: nMel)
            for m in 0..<nMel {
                var sum: Float = 0
                for k in 0..<melFilters[m].count {
                    sum += melFilters[m][k] * powerSpec[k]
                }
                melFrame[m] = sum
            }

            // Log compression (log10, clamp to avoid log(0))
            let epsilon: Float = 1e-10
            for i in 0..<melFrame.count {
                melFrame[i] = max(melFrame[i], epsilon)
            }
            var logMelFrame = [Float](repeating: 0, count: nMel)
            var nMelInt32 = Int32(nMel)
            vvlog10f(&logMelFrame, &melFrame, &nMelInt32)

            result.append(logMelFrame)
        }

        return result
    }

    // MARK: - Private Helpers

    /// Frames the signal with overlapping windows.
    private static func frameSignal(
        _ samples: [Float],
        frameLength: Int,
        frameShift: Int
    ) -> [[Float]] {
        let n = samples.count
        guard n >= frameLength else { return [] }

        let nFrames = (n - frameLength) / frameShift + 1
        var frames: [[Float]] = []
        frames.reserveCapacity(nFrames)

        for i in 0..<nFrames {
            let start = i * frameShift
            let frame = Array(samples[start..<start + frameLength])
            frames.append(frame)
        }

        return frames
    }

    /// Creates a Mel filterbank matrix of shape [nMel × (nFft/2+1)].
    private static func createMelFilterbank(
        nFft: Int,
        sampleRate: Float,
        nMel: Int
    ) -> [[Float]] {
        let nFreqBins = nFft / 2 + 1

        // Convert Hz to Mel
        func hzToMel(_ hz: Float) -> Float {
            return 2595.0 * log10(1.0 + hz / 700.0)
        }

        func melToHz(_ mel: Float) -> Float {
            return 700.0 * (pow(10.0, mel / 2595.0) - 1.0)
        }

        let lowMel = hzToMel(0)
        let highMel = hzToMel(sampleRate / 2)
        let melPoints = (0..<(nMel + 2)).map { i -> Float in
            lowMel + Float(i) * (highMel - lowMel) / Float(nMel + 1)
        }

        // Convert mel points to FFT bin indices
        let fftFreqResolution = sampleRate / Float(nFft)
        let binIndices = melPoints.map { melPoint -> Float in
            let hz = melToHz(melPoint)
            return hz / fftFreqResolution
        }

        var filters: [[Float]] = []
        for m in 1...nMel {
            var filter = [Float](repeating: 0, count: nFreqBins)
            let left = binIndices[m - 1]
            let center = binIndices[m]
            let right = binIndices[m + 1]

            for k in 0..<nFreqBins {
                let fk = Float(k)
                if fk >= left && fk <= center {
                    filter[k] = (fk - left) / (center - left)
                } else if fk > center && fk <= right {
                    filter[k] = (right - fk) / (right - center)
                }
            }
            filters.append(filter)
        }

        return filters
    }
}
