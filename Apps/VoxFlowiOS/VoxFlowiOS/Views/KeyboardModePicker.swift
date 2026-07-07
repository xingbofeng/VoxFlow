// DictusApp/Views/KeyboardModePicker.swift adapted for Mashangxie.
// Reusable default layer picker with segmented control and miniature previews.
import Shared
import SwiftUI

struct DefaultLayerPicker: View {
    @AppStorage(SharedKeys.defaultKeyboardLayer, store: AppGroup.preferences)
    private var selectedLayer: String = DefaultKeyboardLayer.letters.rawValue

    var body: some View {
        VStack(spacing: 16) {
            Picker(L10n.t("onboarding.mode.picker"), selection: $selectedLayer) {
                Text("ABC").tag(DefaultKeyboardLayer.letters.rawValue)
                Text("123").tag(DefaultKeyboardLayer.numbers.rawValue)
            }
            .pickerStyle(.segmented)

            previewForLayer
                .id(selectedLayer)
                .frame(height: 140)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.secondarySystemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.dictusAccent.opacity(0.15), lineWidth: 1)
                )
                .allowsHitTesting(false)
                .animation(.easeInOut(duration: 0.2), value: selectedLayer)
        }
    }

    @ViewBuilder
    private var previewForLayer: some View {
        if selectedLayer == DefaultKeyboardLayer.numbers.rawValue {
            numbersModePreview
        } else {
            lettersModePreview
        }
    }

    private var toolbarPreview: some View {
        HStack {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(Color(.systemGray))
            Spacer()
            Capsule()
                .fill(Color.dictusAccent)
                .frame(width: 36, height: 18)
                .overlay(
                    Image(systemName: "mic.fill")
                        .font(.system(size: 8))
                        .foregroundColor(.white)
                )
        }
        .frame(height: 22)
    }

    private var lettersModePreview: some View {
        VStack(spacing: 3) {
            toolbarPreview
            let rows = [
                ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"],
                ["A", "S", "D", "F", "G", "H", "J", "K", "L"],
                ["Z", "X", "C", "V", "B", "N", "M"],
                ["123", L10n.t("keyboard.space")]
            ]
            ForEach(0..<rows.count, id: \.self) { rowIndex in
                HStack(spacing: 2) {
                    ForEach(rows[rowIndex], id: \.self) { label in
                        miniKey(
                            label,
                            width: rowIndex == 3 && label == "123" ? 32 : nil,
                            isSpace: rowIndex == 3 && label != "123",
                            isSpecial: rowIndex == 3 && label == "123"
                        )
                    }
                }
            }
        }
        .padding(10)
    }

    private var numbersModePreview: some View {
        VStack(spacing: 3) {
            toolbarPreview
            HStack(spacing: 2) {
                ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"], id: \.self) { num in
                    miniKey(num, isHighlighted: true)
                }
            }
            let symbolRows = [
                ["-", "/", ":", ";", "(", ")", "&", "@", "\""],
                [".", ",", "?", "!", "'"]
            ]
            ForEach(0..<symbolRows.count, id: \.self) { rowIndex in
                HStack(spacing: 2) {
                    ForEach(symbolRows[rowIndex], id: \.self) { symbol in
                        miniKey(symbol)
                    }
                }
            }
            HStack(spacing: 2) {
                miniKey("ABC", width: 32, isSpecial: true)
                miniKey(L10n.t("keyboard.space"), isSpace: true)
            }
        }
        .padding(10)
    }

    private func miniKey(
        _ label: String,
        width: CGFloat? = nil,
        isSpace: Bool = false,
        isSpecial: Bool = false,
        isHighlighted: Bool = false
    ) -> some View {
        let bg: Color = isSpecial
            ? Color(.systemGray4)
            : isHighlighted
                ? Color.dictusAccent.opacity(0.2)
                : Color(.systemGray5)

        return Text(label)
            .font(.system(size: isSpace ? 6 : 7, weight: .medium))
            .foregroundStyle(isHighlighted ? Color.dictusAccent : .primary)
            .frame(maxWidth: width ?? .infinity, minHeight: 16)
            .background(
                RoundedRectangle(cornerRadius: 2)
                    .fill(bg)
            )
    }
}
