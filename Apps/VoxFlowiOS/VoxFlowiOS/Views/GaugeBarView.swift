// DictusApp/Views/GaugeBarView.swift
// Reusable 5-segment gauge bar for model accuracy/speed display.
import SwiftUI
import Shared

/// A 5-segment gauge bar that fills segments based on a 0.0-1.0 value.
///
/// WHY a reusable component (not inline in ModelCardView):
/// Gauge bars are used twice per model card (accuracy + speed) and could be
/// reused elsewhere. Extracting keeps ModelCardView focused on layout.
///
/// HOW segment fill works:
/// `filledSegments = Int(round(value * Double(segments)))` converts the 0-1
/// score into a discrete count. For example, 0.6 with 5 segments = 3 filled.
struct GaugeBarView: View {
    /// Score value from 0.0 (empty) to 1.0 (full).
    let value: Double
    /// Label displayed above the gauge (e.g. "Accuracy", "Speed").
    let label: String
    /// Color for filled segments.
    let color: Color
    /// Number of segments in the gauge bar.
    var segments: Int = 5

    /// How many segments should be filled based on the value.
    private var filledSegments: Int {
        Int(round(value * Double(segments)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.dictusCaption)
                .foregroundStyle(.secondary)

            HStack(spacing: 2) {
                ForEach(0..<segments, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(index < filledSegments ? color : color.opacity(0.15))
                        .frame(height: 6)
                }
            }
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        GaugeBarView(value: 0.6, label: "Accuracy", color: .dictusAccent)
        GaugeBarView(value: 0.8, label: "Speed", color: .dictusAccentHighlight)
    }
    .padding()
    .background(Color.dictusBackground)
}
