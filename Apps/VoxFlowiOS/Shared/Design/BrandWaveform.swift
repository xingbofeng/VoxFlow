// DictusCore/Sources/DictusCore/Design/BrandWaveform.swift
// Multi-bar waveform with brand-inspired colors (blue gradient center, white opacity sides).
import SwiftUI
import QuartzCore

@MainActor
final class BrandWaveformDriver: ObservableObject {
    @Published private(set) var displayLevels: [Float] = Array(repeating: 0, count: 30)
    @Published private(set) var processingPhase: Double = 0
    @Published private(set) var renderTick: Int = 0
    @Published private(set) var isProcessing = false

    private let barCount = 30
    private let smoothingFactor: Float = 0.3
    private let decayFactor: Float = 0.85

    private var energyLevels: [Float] = []
    private var isActive = false
    private var displayLink: CADisplayLink?
    private var lastRenderTime: Date = .distantPast
    private var lastHeartbeatTime: Date = .distantPast

    deinit {
        // CADisplayLink cleanup is handled by stopLoop(); Swift 6 prevents
        // accessing main-actor isolated displayLink from nonisolated deinit.
    }

    func update(energyLevels: [Float], isProcessing: Bool, isActive: Bool) {
        self.energyLevels = energyLevels
        self.isProcessing = isProcessing
        self.isActive = isActive

        if !isProcessing {
            processingPhase = 0
        }

        if !isActive {
            displayLevels = targetLevels()
        }

        updateLoopState()
    }

    func forceStop() {
        stopLoop()
    }

    private func updateLoopState() {
        if isActive {
            startLoopIfNeeded()
        } else {
            stopLoop()
        }
    }

    private func startLoopIfNeeded() {
        guard displayLink == nil else { return }

        let link = CADisplayLink(target: self, selector: #selector(handleDisplayLink))
        link.add(to: .main, forMode: .common)
        displayLink = link
        lastRenderTime = Date()
        lastHeartbeatTime = .distantPast

        PersistentLog.log(.waveformAppeared(
            refreshID: renderTick,
            isProcessing: isProcessing,
            energyCount: energyLevels.count,
            killedState: false
        ))
    }

    private func stopLoop() {
        guard displayLink != nil else { return }

        displayLink?.invalidate()
        displayLink = nil

        PersistentLog.log(.waveformDisappeared(
            refreshID: renderTick,
            renderTick: renderTick
        ))
    }

    @objc
    private func handleDisplayLink(_ link: CADisplayLink) {
        let now = Date()

        if lastRenderTime != .distantPast {
            let gapMs = Int(now.timeIntervalSince(lastRenderTime) * 1000)
            if gapMs > 500 {
                PersistentLog.log(.waveformStall(
                    gapMs: gapMs,
                    renderTick: renderTick,
                    energyCount: energyLevels.count
                ))
            }
        }
        lastRenderTime = now

        if isProcessing {
            processingPhase += link.duration / 2.0
        } else {
            tickLevels()
        }

        if now.timeIntervalSince(lastHeartbeatTime) >= 2.0 {
            let sourceLevels: [Float] = isProcessing
                ? (0..<barCount).map { processingEnergy(at: $0, phase: processingPhase) }
                : displayLevels
            let avg = sourceLevels.isEmpty ? Float(0) : sourceLevels.reduce(0, +) / Float(sourceLevels.count)
            PersistentLog.log(.waveformHeartbeat(
                renderTick: renderTick,
                avgLevel: avg,
                energyCount: energyLevels.count
            ))
            lastHeartbeatTime = now
        }

        renderTick += 1
    }

    private func tickLevels() {
        let targets = targetLevels()
        var updated = displayLevels

        for i in 0..<barCount {
            let target = targets[i]
            let current = updated[i]

            if target > current {
                updated[i] = current + (target - current) * smoothingFactor
            } else {
                updated[i] = target + (current - target) * decayFactor
            }

            if updated[i] < 0.005 {
                updated[i] = 0
            }
        }

        displayLevels = updated
    }

    func processingEnergy(at index: Int, phase: Double) -> Float {
        let normalizedIndex = Double(index) / Double(max(barCount - 1, 1))
        let sineValue = sin(2 * .pi * (normalizedIndex + phase))
        return Float(0.2 + 0.25 * (sineValue + 1.0))
    }

    private func targetLevels() -> [Float] {
        guard !energyLevels.isEmpty else {
            return Array(repeating: Float(0), count: barCount)
        }

        var result = [Float]()
        result.reserveCapacity(barCount)

        for index in 0..<barCount {
            let position = Float(index) / Float(max(barCount - 1, 1))
            let arrayIndex = position * Float(energyLevels.count - 1)
            let lower = Int(arrayIndex)
            let upper = min(lower + 1, energyLevels.count - 1)
            let fraction = arrayIndex - Float(lower)
            let value = energyLevels[lower] * (1 - fraction) + energyLevels[upper] * fraction
            let thresholded = value < 0.05 ? Float(0) : value
            result.append(min(max(thresholded, 0), 1))
        }

        return result
    }
}

/// Multi-bar audio waveform styled with Dictus brand colors.
///
/// WHY multi-bar instead of 3-bar logo:
/// 3 bars felt static and logo-like, not like a real audio visualizer.
/// This uses 30 bars for fluid audio feedback, but keeps brand identity through
/// the color scheme: center bars use the blue gradient, outer bars use white at
/// decreasing opacity -- echoing the logo's asymmetric bar styling.
///
/// WHY GeometryReader for bar width:
/// Bar width adapts automatically to fit available space in each context.
/// The waveform fills the space whether it appears in the recording overlay
/// (full keyboard width), the HomeView card (narrower), or RecordingView (full screen).
public struct BrandWaveform: View {
    /// Array of energy levels (0.0-1.0) for each bar. Count determines bar count.
    public let energyLevels: [Float]

    /// Fixed height of the waveform container. Bars grow within this space.
    public var maxHeight: CGFloat = 80

    /// When true, generates a synthetic sinusoidal wave pattern instead of using energyLevels.
    /// WHY: During transcription processing, the audio engine is idle but we want continuous
    /// visual feedback. A traveling sine wave maintains waveform continuity from the recording
    /// state while indicating "processing" rather than "recording".
    public var isProcessing: Bool = false

    /// When false, pauses the TimelineView animation schedule (stops CADisplayLink).
    /// WHY: Some hosts need a hard kill switch when the view is still structurally
    /// alive for a moment (for example during keyboard overlay transitions). This
    /// must stop both live recording animation and the processing sine wave.
    public var isActive: Bool = true

    public init(energyLevels: [Float] = [], maxHeight: CGFloat = 80,
                isProcessing: Bool = false, isActive: Bool = true) {
        self.energyLevels = energyLevels
        self.maxHeight = maxHeight
        self.isProcessing = isProcessing
        self.isActive = isActive
    }

    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var driver = BrandWaveformDriver()

    /// Number of bars to display.
    private let barCount = 30

    private let barSpacing: CGFloat = 2

    public var body: some View {
        waveformContent
            .onAppear {
                driver.update(
                    energyLevels: energyLevels,
                    isProcessing: isProcessing,
                    isActive: isActive
                )
            }
            .onDisappear {
                driver.forceStop()
            }
            .onChange(of: energyLevels) { _, newLevels in
                driver.update(
                    energyLevels: newLevels,
                    isProcessing: isProcessing,
                    isActive: isActive
                )
            }
            .onChange(of: isProcessing) { _, newValue in
                driver.update(
                    energyLevels: energyLevels,
                    isProcessing: newValue,
                    isActive: isActive
                )
            }
            .onChange(of: isActive) { _, newValue in
                driver.update(
                    energyLevels: energyLevels,
                    isProcessing: isProcessing,
                    isActive: newValue
                )
            }
    }

    /// Canvas-based rendering for 60fps waveform.
    ///
    /// WHY Canvas instead of ForEach + RoundedRectangle:
    /// ForEach creates 30 separate SwiftUI views, each with its own layout pass.
    /// Canvas renders all 30 bars in a single GPU draw call, which is significantly
    /// more efficient and eliminates frame drops during rapid energy level updates.
    ///
    /// WHY zero minHeight in non-processing mode:
    /// The old minHeight of 4pt caused visible micro-movements at zero energy,
    /// making the waveform appear "alive" even when silent. Setting minHeight = 0
    /// means bars completely disappear at zero energy -- perfectly still.
    private var waveformContent: some View {
        Canvas { context, size in
            let _ = driver.renderTick
            let totalSpacing = barSpacing * CGFloat(barCount - 1)
            let barWidth = max((size.width - totalSpacing) / CGFloat(barCount), 2)

            for index in 0..<barCount {
                let energy: Float
                if driver.isProcessing {
                    energy = driver.processingEnergy(at: index, phase: driver.processingPhase)
                } else {
                    energy = index < driver.displayLevels.count ? driver.displayLevels[index] : 0
                }

                // Minimum bar height so the waveform baseline is always visible,
                // even in complete silence. 2pt = thin line, enough to see the
                // colored bar pattern (blue center, gray edges) without looking "active".
                let minHeight: CGFloat = driver.isProcessing ? 4 : 2
                let height = max(minHeight + CGFloat(energy) * (maxHeight - minHeight), minHeight)

                let x = CGFloat(index) * (barWidth + barSpacing)
                let y = (size.height - height) / 2
                let rect = CGRect(x: x, y: y, width: barWidth, height: max(height, 0))
                let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)

                context.fill(path, with: .color(resolvedBarColor(at: index)))
            }
        }
        .frame(height: maxHeight)
    }

    /// Brand-inspired color resolved to a plain Color for Canvas rendering.
    ///
    /// WHY plain Color instead of ShapeStyle/LinearGradient:
    /// Canvas's `context.fill(path, with:)` accepts `Shading` not `ShapeStyle`.
    /// Per-path gradients aren't practical in Canvas. Instead, center bars use the
    /// brand blue midpoint color (dictusGradientStart) which is visually close to
    /// the old top-to-bottom gradient. A minor simplification for major perf gain.
    private func resolvedBarColor(at index: Int) -> Color {
        // Distance from center (0.0 = center, 1.0 = edge)
        let center = Float(barCount - 1) / 2.0
        let distanceFromCenter = abs(Float(index) - center) / center

        // Center bars: brand blue, edge bars: white/gray with decreasing opacity
        if distanceFromCenter < 0.4 {
            // Inner 40%: solid brand blue (midpoint of old gradient)
            return .dictusGradientStart
        } else {
            // Outer 60%: adaptive color with opacity decreasing toward edges
            let opacity = Double(1.0 - distanceFromCenter) * 0.9 + 0.15
            let barColor: Color = colorScheme == .dark ? .white : .gray
            return barColor.opacity(opacity)
        }
    }
}

#Preview("Idle") {
    ZStack {
        Color(hex: 0x0A1628).ignoresSafeArea()
        BrandWaveform(energyLevels: Array(repeating: Float(0), count: 30))
    }
}

#Preview("Active") {
    ZStack {
        Color(hex: 0x0A1628).ignoresSafeArea()
        BrandWaveform(energyLevels: (0..<30).map { i in
            Float.random(in: 0.2...0.8)
        })
    }
}

#Preview("Processing") {
    ZStack {
        Color(hex: 0x0A1628).ignoresSafeArea()
        BrandWaveform(maxHeight: 120, isProcessing: true)
            .opacity(0.3)
            .padding(.horizontal)
    }
}
