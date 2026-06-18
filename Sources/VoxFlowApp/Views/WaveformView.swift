import AppKit

/// A custom NSView that renders 5 animated vertical bars driven by real-time audio RMS levels.
/// Bars use weighted heights (center-highest), attack/release smoothing, and organic random jitter.
final class WaveformView: NSView {
    // MARK: - Constants

    private let barCornerRadius: CGFloat = 2.0
    private let barFillColor = CGColor(red: 0.055, green: 0.420, blue: 0.345, alpha: 0.88)

    // MARK: - State

    private var targetRMS: CGFloat = 0.0
    private var barHeights: [CGFloat] = [3, 3, 3, 3, 3]
    private var animationTimer: Timer?
    private var model = WaveformModel()

    // MARK: - Lifecycle

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Public

    /// Update the RMS level that drives the waveform. Call on any thread.
    func updateRMS(_ rms: Float) {
        targetRMS = CGFloat(rms)
    }

    func startAnimation() {
        guard animationTimer == nil else { return }
        animationTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0 / 60.0,
            repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
    }

    func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    func reset() {
        targetRMS = 0
        model = WaveformModel()
        barHeights = Array(
            repeating: WaveformModel.minBarHeight,
            count: WaveformModel.barCount
        )
        needsDisplay = true
    }

    // MARK: - Animation

    private func tick() {
        barHeights = model.update(targetRMS: targetRMS) {
            CGFloat.random(in: -WaveformModel.jitterRange...WaveformModel.jitterRange)
        }

        needsDisplay = true
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let startX = (bounds.width - WaveformModel.totalWidth) / 2.0

        guard let context = NSGraphicsContext.current?.cgContext else { return }

        for i in 0..<WaveformModel.barCount {
            let x = startX + CGFloat(i) * (WaveformModel.barWidth + WaveformModel.barSpacing)
            let height = barHeights[i]
            let y = (bounds.height - height) / 2.0  // Vertically centered

            let barRect = CGRect(x: x, y: y, width: WaveformModel.barWidth, height: height)
            let path = CGPath(
                roundedRect: barRect,
                cornerWidth: barCornerRadius,
                cornerHeight: barCornerRadius,
                transform: nil
            )

            context.addPath(path)

            context.setFillColor(barFillColor)
            context.fillPath()
        }
    }
}
