import SwiftUI
import QuartzCore
import Shared

@MainActor
final class KeyboardWaveformDriver: ObservableObject {
    static let shared = KeyboardWaveformDriver()
    private let instanceID = String(UUID().uuidString.prefix(8))

    @Published private(set) var displayLevels: [Float] = Array(repeating: 0, count: 30)
    @Published private(set) var isProcessing = false
    @Published private(set) var processingPhase: Double = 0
    @Published private(set) var renderTick: Int = 0

    private let barCount = 30
    private let smoothingFactor: Float = 0.3
    private let decayFactor: Float = 0.85

    private var status: DictationStatus = .idle
    private var energyLevels: [Float] = []
    private var isVisible = false
    private var activePresenterID: String?
    private var displayLink: CADisplayLink?
    private var lastTickTime: CFTimeInterval?
    private var lastHeartbeatTime: Date = .distantPast

    private init() {
        logProbe("init")
    }

    deinit {
        // CADisplayLink cleanup handled elsewhere
    }

    func sync(presenterID: String, status: DictationStatus, energyLevels: [Float], isVisible: Bool) {
        let ownsPresentation = activePresenterID == presenterID
        if !isVisible && !ownsPresentation && activePresenterID != nil {
            return
        }

        if isVisible {
            activePresenterID = presenterID
        } else if ownsPresentation {
            activePresenterID = nil
        }

        self.status = status
        self.energyLevels = energyLevels
        self.isVisible = isVisible
        isProcessing = status == .transcribing

        if status != .transcribing {
            processingPhase = 0
        }

        if status == .requested || status == .idle || status == .ready {
            displayLevels = Array(repeating: 0, count: barCount)
        }

        if !isVisible {
            lastTickTime = nil
            lastHeartbeatTime = .distantPast
        }

        updateDisplayLinkState()
    }

    private func updateDisplayLinkState() {
        let shouldRun = isVisible && (status == .recording || status == .transcribing)

        if shouldRun {
            startDisplayLinkIfNeeded()
        } else {
            stopDisplayLink()
        }
    }

    private func startDisplayLinkIfNeeded() {
        guard displayLink == nil else { return }

        let link = CADisplayLink(target: self, selector: #selector(handleDisplayLink))
        link.add(to: .main, forMode: .common)
        displayLink = link

        PersistentLog.log(.waveformAppeared(
            refreshID: renderTick,
            isProcessing: status == .transcribing,
            energyCount: energyLevels.count,
            killedState: false
        ))
        logProbe("displayLinkStarted", details: "status=\(status.rawValue) energyCount=\(energyLevels.count) renderTick=\(renderTick)")
    }

    private func stopDisplayLink() {
        guard displayLink != nil else { return }

        // CADisplayLink cleanup handled elsewhere
        displayLink = nil
        lastTickTime = nil

        PersistentLog.log(.waveformDisappeared(
            refreshID: renderTick,
            renderTick: renderTick
        ))
        logProbe("displayLinkStopped", details: "status=\(status.rawValue) renderTick=\(renderTick)")
    }

    @objc
    private func handleDisplayLink(_ link: CADisplayLink) {
        let timestamp = link.timestamp
        let previousTimestamp = lastTickTime
        lastTickTime = timestamp

        if let previousTimestamp {
            let gapMs = Int((timestamp - previousTimestamp) * 1000)
            if gapMs > 500 {
                PersistentLog.log(.waveformStall(
                    gapMs: gapMs,
                    renderTick: renderTick,
                    energyCount: energyLevels.count
                ))
            }
        }

        switch status {
        case .recording:
            tickRecording()
        case .transcribing:
            processingPhase += link.duration / 2.0
        default:
            break
        }

        renderTick += 1
        logHeartbeatIfNeeded()
    }

    private func tickRecording() {
        let targets = targetLevels()
        var updated = displayLevels

        for index in 0..<barCount {
            let target = targets[index]
            let current = updated[index]

            if target > current {
                updated[index] = current + (target - current) * smoothingFactor
            } else {
                updated[index] = target + (current - target) * decayFactor
            }

            if updated[index] < 0.005 {
                updated[index] = 0
            }
        }

        displayLevels = updated
    }

    private func logHeartbeatIfNeeded() {
        let now = Date()
        guard now.timeIntervalSince(lastHeartbeatTime) >= 2.0 else { return }

        let targets = targetLevels()

        let sourceLevels: [Float]
        if status == .transcribing {
            sourceLevels = (0..<barCount).map { processingEnergy(at: $0, phase: processingPhase) }
        } else {
            sourceLevels = displayLevels
        }

        let average = sourceLevels.isEmpty ? Float(0) : sourceLevels.reduce(0, +) / Float(sourceLevels.count)
        PersistentLog.log(.waveformHeartbeat(
            renderTick: renderTick,
            avgLevel: average,
            energyCount: energyLevels.count
        ))
        if status == .recording {
            logProbe(
                "waveformShape",
                details: "target{\(waveformStatsDetails(targets))} display{\(waveformStatsDetails(displayLevels))}"
            )
        }
        lastHeartbeatTime = now
    }

    private func targetLevels() -> [Float] {
        guard !energyLevels.isEmpty else {
            return Array(repeating: 0, count: barCount)
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

    func processingEnergy(at index: Int, phase: Double) -> Float {
        let normalizedIndex = Double(index) / Double(max(barCount - 1, 1))
        let sineValue = sin(2 * .pi * (normalizedIndex + phase))
        return Float(0.2 + 0.25 * (sineValue + 1.0))
    }

    private func logProbe(_ action: String, details: String = "") {
        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardWaveformDriver",
            instanceID: instanceID,
            action: action,
            details: details
        ))
    }

    private func waveformStatsDetails(_ values: [Float]) -> String {
        guard !values.isEmpty else { return "count=0" }
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 0
        let spread = maxValue - minValue
        let first = values.first ?? 0
        let middle = values[values.count / 2]
        let last = values.last ?? 0
        return String(
            format: "count=%d min=%.3f max=%.3f spread=%.3f first=%.3f mid=%.3f last=%.3f",
            values.count,
            minValue,
            maxValue,
            spread,
            first,
            middle,
            last
        )
    }
}

struct KeyboardWaveformView: View {
    let maxHeight: CGFloat
    @ObservedObject var driver: KeyboardWaveformDriver

    @Environment(\.colorScheme) private var colorScheme

    private let barCount = 30
    private let barSpacing: CGFloat = 2

    var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                let energy: Float = driver.isProcessing
                    ? driver.processingEnergy(at: index, phase: driver.processingPhase)
                    : (index < driver.displayLevels.count ? driver.displayLevels[index] : 0)

                let minHeight: CGFloat = driver.isProcessing ? 4 : 2
                let height = max(minHeight + CGFloat(energy) * (maxHeight - minHeight), minHeight)

                Capsule()
                    .fill(resolvedBarColor(at: index))
                    .frame(height: height)
            }
        }
        .frame(height: maxHeight)
    }

    private func resolvedBarColor(at index: Int) -> Color {
        let center = Float(barCount - 1) / 2.0
        let distanceFromCenter = abs(Float(index) - center) / center

        if distanceFromCenter < 0.4 {
            return .dictusGradientStart
        }

        let opacity = Double(1.0 - distanceFromCenter) * 0.9 + 0.15
        let barColor: Color = colorScheme == .dark ? .white : .gray
        return barColor.opacity(opacity)
    }
}
