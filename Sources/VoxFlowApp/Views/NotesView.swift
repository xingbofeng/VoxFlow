import AppKit
import SwiftUI

struct NotesView: View {
    @ObservedObject var viewModel: NotesViewModel
    @State private var isSearchPresented = false
    @State private var isEditorFocused = false
    @State private var editorSelection = NSRange(location: 0, length: 0)

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 48) {
                    quickCapture
                    recentNotes
                }
                .padding(.horizontal, 42)
                .padding(.vertical, 36)
                .frame(maxWidth: 980)
                .frame(maxWidth: .infinity)
            }

            notePreviewOverlay
        }
        .background(AppTheme.ColorToken.pageBackground)
        .tint(AppTheme.ColorToken.accent)
        .actionFeedbackOverlay(
            message: viewModel.lastActionMessage,
            error: viewModel.lastError,
            onDismiss: viewModel.clearFeedback
        )
        .onAppear {
            viewModel.loadIfNeeded()
            registerNotesCapture()
        }
        .onDisappear {
            NotesCaptureCoordinator.shared.reset()
        }
        .onChange(of: isEditorFocused) { _, focused in
            NotesCaptureCoordinator.shared.setEditorFocused(focused)
        }
        .onChange(of: editorSelection) { _, selection in
            NotesCaptureCoordinator.shared.editorSelection = selection
        }
        .onChange(of: viewModel.recordingState) { _, state in
            NotesCaptureCoordinator.shared.isRecording = state == .recording
        }
    }

    @ViewBuilder
    private var notePreviewOverlay: some View {
        if let note = viewModel.previewedNote {
            ZStack {
                Color.black.opacity(0.24)
                    .ignoresSafeArea()
                    .onTapGesture {
                        viewModel.dismissPreview()
                    }

                NoteMarkdownPreviewModal(note: note, onClose: viewModel.dismissPreview)
                    .onTapGesture {}
            }
            .onExitCommand(perform: viewModel.dismissPreview)
        }
    }

    private var quickCapture: some View {
        VStack(spacing: 24) {
            Text(L10n.localize("notes.view.quick_capture_title", comment: "Quick capture title"))
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(AppTheme.ColorToken.primaryText)

            VStack(alignment: .leading, spacing: 18) {
                ZStack(alignment: .topLeading) {
                    CursorTrackingTextEditor(
                        text: $viewModel.draftBodyMarkdown,
                        selection: $editorSelection,
                        isFocused: $isEditorFocused
                    )
                        .frame(minHeight: 128)

                    if viewModel.draftBodyMarkdown.isEmpty {
                        Text(recordingPlaceholder)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(AppTheme.ColorToken.secondaryText.opacity(0.72))
                            .padding(.top, 14)
                            .padding(.leading, 18)
                            .allowsHitTesting(false)
                    }
                }

                HStack(alignment: .center) {
                    Text(
                        L10n.format("notes.editor.character_count_format", comment: "Character count in quick capture",
                            viewModel.characterCount
                        )
                    )
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)

                    Spacer()

                    if viewModel.recordingState != .idle || !viewModel.draftBodyMarkdown.isEmpty {
                        Button(L10n.localize("notes.editor.finish_action", comment: "Complete quick capture")) {
                            completeQuickCapture()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.recordingState == .finishing)
                    }
                }
            }
            .padding(24)
            .overlay(alignment: .topTrailing) {
                recordButton
                    .padding(20)
            }
            .background(AppTheme.ColorToken.panelBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(AppTheme.ColorToken.panelStroke, lineWidth: AppTheme.Border.panelLineWidth)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: AppTheme.ColorToken.accent.opacity(0.07), radius: 18, y: 8)
            .frame(maxWidth: 760)
        }
    }

    private var recordButton: some View {
        Button {
            switch viewModel.recordingState {
            case .idle:
                Task { await viewModel.startRecording(replacing: editorSelection) }
            case .recording:
                viewModel.finishRecording()
            case .finishing:
                break
            }
        } label: {
            Image(systemName: recordButtonIcon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(recordButtonBackground)
                .clipShape(Circle())
                .shadow(color: AppTheme.ColorToken.accent.opacity(0.20), radius: 7, y: 3)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.recordingState == .finishing)
        .help(
            viewModel.recordingState == .recording
                ? L10n.localize("notes.recording.finish_help", comment: "Finish recording")
                : L10n.localize("notes.recording.start_help", comment: "Start recording")
        )
    }

    private var recentNotes: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Text(L10n.localize("notes.view.recent_notes_title", comment: "Recent notes title"))
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                if isSearchPresented {
                    TextField(
                        L10n.localize("notes.view.search_placeholder", comment: "Search notes placeholder"),
                        text: $viewModel.searchQuery
                    )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                        .onChange(of: viewModel.searchQuery) { _, query in
                            viewModel.search(query)
                        }
                }
                iconButton(
                    systemName: "magnifyingglass",
                    help: L10n.localize("notes.view.search_help", comment: "Help for notes search")
                ) {
                    isSearchPresented.toggle()
                    if !isSearchPresented {
                        viewModel.search("")
                    }
                }
                iconButton(
                    systemName: "list.bullet",
                    help: L10n.localize("notes.view.show_as_grid_help", comment: "Show as grid/list help")
                ) {}
            }

            Divider()

            if viewModel.notes.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "note.text")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText.opacity(0.55))
                        .frame(width: 64, height: 64)
                        .background(AppTheme.ColorToken.accentSoft)
                        .clipShape(Circle())
                    Text(L10n.localize("notes.view.empty_state", comment: "No notes placeholder text"))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                        .textSelection(.disabled)
                }
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 250), spacing: 14)],
                    spacing: 14
                ) {
                    ForEach(viewModel.notes, id: \.id) { note in
                        noteCard(note)
                    }
                }
            }
        }
    }

    private func noteCard(_ note: NoteRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(note.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.ColorToken.primaryText)
                .lineLimit(1)
            Text(note.bodyMarkdown)
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
                .lineLimit(3)
                .frame(maxWidth: .infinity, minHeight: 38, alignment: .topLeading)

            HStack {
                Text(note.updatedAt.formatted(.dateTime.month().day()))
                Spacer()
                Text(note.updatedAt.formatted(.dateTime.hour().minute()))
                noteAction(
                    systemName: "square.and.arrow.up",
                    help: L10n.localize("notes.view.export_markdown_help", comment: "Note markdown export tooltip")
                ) {
                    perform { _ = try viewModel.exportMarkdown(noteID: note.id) }
                }
                noteAction(
                    systemName: "trash",
                    help: L10n.localize("notes.view.delete_help", comment: "Note delete tooltip")
                ) {
                    perform { try viewModel.deleteNote(id: note.id) }
                }
                .foregroundStyle(.red)
            }
            .font(.system(size: 11))
            .foregroundStyle(AppTheme.ColorToken.secondaryText)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            viewModel.selectedNoteID == note.id
                ? AppTheme.ColorToken.selectionBackground
                : AppTheme.ColorToken.panelBackground
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                .stroke(
                    viewModel.selectedNoteID == note.id
                        ? AppTheme.ColorToken.accent.opacity(0.36)
                        : AppTheme.ColorToken.panelStroke
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
        .shadow(color: AppTheme.ColorToken.accent.opacity(0.03), radius: 5, y: 2)
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.previewNote(id: note.id)
        }
    }

    private func iconButton(
        systemName: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(AppTheme.ColorToken.secondaryText)
        .help(help)
    }

    private func noteAction(
        systemName: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var recordingPlaceholder: String {
        switch viewModel.recordingState {
        case .idle:
            return L10n.localize("notes.recording.placeholder_idle", comment: "Empty recording placeholder when idle")
        case .recording:
            return L10n.localize("notes.recording.placeholder_recording", comment: "Recording placeholder while listening")
        case .finishing:
            return L10n.localize("notes.recording.placeholder_finishing", comment: "Recording placeholder while finalizing")
        }
    }

    private var recordButtonIcon: String {
        switch viewModel.recordingState {
        case .idle:
            return "mic"
        case .recording:
            return "checkmark"
        case .finishing:
            return "ellipsis"
        }
    }

    private var recordButtonBackground: Color {
        switch viewModel.recordingState {
        case .idle:
            return AppTheme.ColorToken.primaryText
        case .recording:
            return AppTheme.ColorToken.accent
        case .finishing:
            return AppTheme.ColorToken.accentDark
        }
    }

    private func completeQuickCapture() {
        if viewModel.recordingState == .recording {
            viewModel.finishRecording()
            return
        }
        guard viewModel.recordingState == .idle else { return }
        perform { try viewModel.saveDraft() }
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            viewModel.report(error: error)
        }
    }

    private func registerNotesCapture() {
        let coordinator = NotesCaptureCoordinator.shared
        coordinator.setEditorFocused(isEditorFocused)
        coordinator.editorSelection = editorSelection
        coordinator.startRecording = { [weak viewModel] in
            guard let viewModel, viewModel.recordingState == .idle else { return }
            await viewModel.startRecording(replacing: coordinator.editorSelection)
            coordinator.isRecording = viewModel.recordingState == .recording
        }
        coordinator.finishRecording = { [weak viewModel] in
            guard let viewModel, viewModel.recordingState == .recording else { return }
            viewModel.finishRecording()
            coordinator.isRecording = false
        }
    }
}

private struct NoteMarkdownPreviewModal: View {
    let note: NoteRecord
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(note.title)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(AppTheme.ColorToken.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(note.updatedAt.formatted(.dateTime.year().month().day().hour().minute()))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                }

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                        .frame(width: 34, height: 34)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(L10n.localize("notes.view.close_preview_help", comment: "Close preview tooltip"))
            }

            Divider()

            ScrollView {
                Text(markdownText)
                    .font(.system(size: 15))
                    .lineSpacing(6)
                    .foregroundStyle(AppTheme.ColorToken.primaryText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.vertical, 4)
            }
        }
        .padding(28)
        .frame(width: 720, height: 560)
        .background(AppTheme.ColorToken.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 28, y: 14)
    }

    private var markdownText: AttributedString {
        (try? AttributedString(markdown: note.bodyMarkdown)) ?? AttributedString(note.bodyMarkdown)
    }
}

private struct CursorTrackingTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange
    @Binding var isFocused: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.font = .systemFont(ofSize: 16)
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.textContainerInset = NSSize(width: 14, height: 12)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.string = text
        textView.setSelectedRange(Self.clamped(selection, in: text))
        scrollView.documentView = textView
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        let clampedSelection = Self.clamped(selection, in: text)
        if textView.selectedRange() != clampedSelection {
            textView.setSelectedRange(clampedSelection)
        }
    }

    private static func clamped(_ range: NSRange, in text: String) -> NSRange {
        let length = (text as NSString).length
        let location = min(max(0, range.location), length)
        return NSRange(
            location: location,
            length: min(max(0, range.length), length - location)
        )
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CursorTrackingTextEditor
        weak var textView: NSTextView?

        init(parent: CursorTrackingTextEditor) {
            self.parent = parent
        }

        func textDidBeginEditing(_ notification: Notification) {
            parent.isFocused = true
        }

        func textDidEndEditing(_ notification: Notification) {
            parent.isFocused = false
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            parent.text = textView.string
            parent.selection = textView.selectedRange()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView else { return }
            parent.selection = textView.selectedRange()
            parent.isFocused = textView.window?.firstResponder === textView
        }
    }
}
