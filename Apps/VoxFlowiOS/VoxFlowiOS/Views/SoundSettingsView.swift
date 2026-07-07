// DictusApp/Views/SoundSettingsView.swift
// Sound feedback settings sub-page: global toggle + volume slider + 3 NavigationLink pickers.
import SwiftUI
import Shared

/// Settings sub-page for configuring recording sound feedback.
///
/// WHY NavigationLink to a picker list (not inline .menu Picker):
/// With 29 sounds, a .menu picker creates a scrollable dropdown overlay that's
/// hard to navigate and buggy on some devices. The iOS Settings pattern for many
/// choices is a NavigationLink that pushes a full-screen list with checkmarks
/// (like Settings > Sounds & Haptics > Ringtone). This also lets us auto-play
/// each sound when the user taps it, removing the need for a separate preview button.
struct SoundSettingsView: View {

    // MARK: - Preferences (App Group persisted)

    @AppStorage(SharedKeys.soundFeedbackEnabled, store: UserDefaults(suiteName: AppGroup.identifier))
    private var soundFeedbackEnabled = false

    @AppStorage(SharedKeys.recordStartSoundName, store: UserDefaults(suiteName: AppGroup.identifier))
    private var recordStartSoundName = "electronic_01f"

    @AppStorage(SharedKeys.recordStopSoundName, store: UserDefaults(suiteName: AppGroup.identifier))
    private var recordStopSoundName = "electronic_02b"

    @AppStorage(SharedKeys.recordCancelSoundName, store: UserDefaults(suiteName: AppGroup.identifier))
    private var recordCancelSoundName = "electronic_03c"

    @AppStorage(SharedKeys.soundVolume, store: UserDefaults(suiteName: AppGroup.identifier))
    private var soundVolume = 0.5

    // MARK: - Body

    var body: some View {
        List {
            // Section 1: Global toggle
            Section {
                Toggle("Enable sounds", isOn: $soundFeedbackEnabled)
            } footer: {
                Text("Sounds follow the iPhone silent switch.")
            }

            // Section 2: Volume slider
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "speaker.fill")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                    Slider(value: $soundVolume, in: 0.05...1.0, step: 0.05)
                        .tint(.accentColor)
                    Image(systemName: "speaker.wave.3.fill")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }
            } header: {
                Text("Volume")
            }
            .disabled(!soundFeedbackEnabled)

            // Section 3: Sound pickers as NavigationLinks
            Section {
                soundNavigationRow(
                    label: "Start",
                    selection: $recordStartSoundName
                )

                soundNavigationRow(
                    label: "End",
                    selection: $recordStopSoundName
                )

                soundNavigationRow(
                    label: "Cancel",
                    selection: $recordCancelSoundName
                )
            } header: {
                Text("Sounds by event")
            }
            .disabled(!soundFeedbackEnabled)
        }
        .scrollContentBackground(.hidden)
        .background(Color.dictusBackground.ignoresSafeArea())
        .navigationTitle("Sounds")
    }

    // MARK: - Private

    /// A NavigationLink row showing label (fixed width) + current value + chevron.
    ///
    /// WHY fixed-width label frame:
    /// Without a fixed width, longer labels like "Début d'enregistrement" push the
    /// value text further right, misaligning it with shorter labels. A fixed leading
    /// column ensures all value texts start at the same horizontal position.
    @ViewBuilder
    private func soundNavigationRow(label: String, selection: Binding<String>) -> some View {
        NavigationLink {
            SoundPickerListView(title: label, selection: selection)
        } label: {
            HStack {
                Text(label)
                Spacer()
                Text(SoundFeedbackService.displayName(for: selection.wrappedValue))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Sound Picker List View

/// Full-screen list of sounds with checkmark selection and auto-preview.
///
/// WHY a separate view (not inline):
/// NavigationLink destination needs its own view to manage the list and handle
/// auto-preview on selection. This is the same pattern as iOS ringtone picker:
/// tap a row → checkmark moves + sound plays.
private struct SoundPickerListView: View {
    let title: String
    @Binding var selection: String

    var body: some View {
        List {
            ForEach(SoundFeedbackService.availableSounds(), id: \.self) { soundName in
                Button {
                    selection = soundName
                    SoundFeedbackService.play(soundName)
                } label: {
                    HStack {
                        Text(SoundFeedbackService.displayName(for: soundName))
                            .foregroundStyle(.primary)
                        Spacer()
                        if soundName == selection {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.dictusBackground.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
