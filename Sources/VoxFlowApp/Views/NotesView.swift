import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct NotesView: View {
    @ObservedObject var viewModel: NotesViewModel
    @State private var isSearchPresented = false
    @State private var isEditorFocused = false
    @State private var editorSelection = NSRange(location: 0, length: 0)

    var body: some View {
        lifecycleContent
    }

    private var chromedContent: some View {
        content
            .background(AppTheme.ColorToken.pageBackground)
            .tint(AppTheme.ColorToken.accent)
            .actionFeedbackOverlay(
                message: viewModel.lastActionMessage,
                error: viewModel.lastError,
                onDismiss: viewModel.clearFeedback
            )
    }

    private var lifecycleContent: some View {
        chromedContent
            .modifier(NotesCaptureLifecycleModifier(
                viewModel: viewModel,
                isEditorFocused: $isEditorFocused,
                editorSelection: $editorSelection,
                registerNotesCapture: registerNotesCapture
            ))
    }

    private var content: AnyView {
        AnyView(ZStack {
            ScrollView {
                VStack(spacing: 42) {
                    quickCapture
                    recentNotes
                }
                .padding(.horizontal, 42)
                .padding(.vertical, 34)
                .frame(maxWidth: 1080)
                .frame(maxWidth: .infinity)
            }

            notePreviewOverlay
        })
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

                NoteMarkdownPreviewModal(
                    viewModel: viewModel,
                    note: note,
                    onClose: viewModel.dismissPreview
                )
                .onTapGesture {}
            }
            .onExitCommand(perform: viewModel.dismissPreview)
            .background(EscapeKeyHandler(onEscape: viewModel.dismissPreview))
        }
    }

    private var quickCapture: some View {
        VStack(spacing: 22) {
            Text(L10n.localize("notes.view.quick_capture_title", comment: "Quick capture title"))
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(AppTheme.ColorToken.primaryText)

            VStack(alignment: .leading, spacing: 16) {
                ZStack(alignment: .topLeading) {
                    CursorTrackingTextEditor(
                        text: $viewModel.draftBodyMarkdown,
                        selection: $editorSelection,
                        isFocused: $isEditorFocused
                    )
                    .frame(height: 132)

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

                    Text(L10n.localize(
                        "notes.quick_capture.hold_to_speak_hint",
                        comment: "Hold to speak hint in quick capture"
                    ))
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText.opacity(0.7))

                    Spacer()

                    Button {
                        viewModel.newDraft()
                    } label: {
                        Label(
                            L10n.localize("notes.action.new_note", comment: "New note"),
                            systemImage: "plus.circle"
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    if viewModel.recordingState != .idle || !viewModel.draftBodyMarkdown.isEmpty {
                        Button(L10n.localize("notes.editor.finish_action", comment: "Complete quick capture")) {
                            completeQuickCapture()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.recordingState == .finishing)
                    }
                }
            }
            .padding(22)
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
            .frame(maxWidth: 800)
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
                // 搜索常驻，不再通过图标切换。
                TextField(
                    L10n.localize("notes.view.search_placeholder", comment: "Search notes placeholder"),
                    text: $viewModel.searchQuery
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
                .onChange(of: viewModel.searchQuery) { _, query in
                    viewModel.search(query)
                }
                Button {
                    viewModel.newDraft()
                } label: {
                    Label(
                        L10n.localize("notes.action.new_note", comment: "New note"),
                        systemImage: "plus"
                    )
                }
                .buttonStyle(.bordered)
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
                    columns: [GridItem(.adaptive(minimum: 300), spacing: 16)],
                    spacing: 16
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
                // 低频操作（导出、删除）收纳到更多菜单。
                Menu {
                    Button {
                        perform { _ = try viewModel.exportMarkdown(noteID: note.id) }
                    } label: {
                        Label(
                            L10n.localize("notes.action.export", comment: "Export note"),
                            systemImage: "square.and.arrow.up"
                        )
                    }
                    Button(role: .destructive) {
                        perform { try viewModel.deleteNote(id: note.id) }
                    } label: {
                        Label(
                            L10n.localize("notes.action.delete", comment: "Delete note action"),
                            systemImage: "trash"
                        )
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L10n.localize("notes.action.more", comment: "More actions"))
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
            return "stop.fill"
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
            coordinator.isRecording = true
            coordinator.recordingStateDidChange?(.recording)
            await viewModel.startRecording(replacing: coordinator.editorSelection)
            coordinator.isRecording = viewModel.recordingState == .recording
            coordinator.recordingStateDidChange?(viewModel.recordingState)
        }
        coordinator.finishRecording = { [weak viewModel] in
            guard let viewModel, viewModel.recordingState == .recording else { return }
            viewModel.finishRecording()
            coordinator.isRecording = false
            coordinator.recordingStateDidChange?(viewModel.recordingState)
        }
        coordinator.cancelRecording = { [weak viewModel] in
            viewModel?.cancelRecording()
            coordinator.isRecording = false
            coordinator.recordingStateDidChange?(.idle)
        }
    }
}

private struct NotesCaptureLifecycleModifier: ViewModifier {
    @ObservedObject var viewModel: NotesViewModel
    @Binding var isEditorFocused: Bool
    @Binding var editorSelection: NSRange
    let registerNotesCapture: () -> Void

    func body(content: Content) -> some View {
        content
            .onAppear {
                viewModel.loadIfNeeded()
                NotesCaptureCoordinator.shared.setViewVisible(true)
                registerNotesCapture()
            }
            .onDisappear {
                if viewModel.recordingState != .idle {
                    viewModel.cancelRecording()
                }
                NotesCaptureCoordinator.shared.setViewVisible(false)
                NotesCaptureCoordinator.shared.reset()
            }
            .onChange(of: viewModel.draftEditorFocusRequest) { _, _ in
                isEditorFocused = true
            }
            .onChange(of: isEditorFocused) { _, focused in
                NotesCaptureCoordinator.shared.setEditorFocused(focused)
            }
            .onChange(of: editorSelection) { _, selection in
                NotesCaptureCoordinator.shared.editorSelection = selection
            }
            .onChange(of: viewModel.editorSelectionRequest) { _, request in
                guard let request else { return }
                editorSelection = request.range
            }
            .onChange(of: viewModel.recordingState) { _, state in
                NotesCaptureCoordinator.shared.isRecording = state == .recording
                NotesCaptureCoordinator.shared.recordingStateDidChange?(state)
            }
            .onChange(of: viewModel.detailMode) { _, mode in
                NotesCaptureCoordinator.shared.setContinuingDictation(mode == .continuingDictation)
            }
    }
}

private struct NoteMarkdownPreviewModal: View {
    @ObservedObject var viewModel: NotesViewModel
    let note: NoteRecord
    let onClose: () -> Void
    @State private var detailEditorSelection = NSRange(location: 0, length: 0)
    @State private var detailEditorFocused = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            bodySection
            Divider()
            footer
        }
        .frame(width: 780, height: 620)
        .background(AppTheme.ColorToken.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 28, y: 14)
        .confirmationDialog(
            L10n.localize("notes.delete.confirm_title", comment: "Delete note confirmation title"),
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(L10n.localize("notes.action.delete", comment: "Delete note action"), role: .destructive) {
                do {
                    try viewModel.deleteNote(id: note.id)
                    onClose()
                } catch {
                    viewModel.report(error: error)
                }
            }
            Button(L10n.localize("transcribe.action.cancel", comment: "Cancel action"), role: .cancel) {}
        }
        .onChange(of: detailEditorFocused) { _, focused in
            NotesCaptureCoordinator.shared.setEditorFocused(focused)
        }
        .onChange(of: detailEditorSelection) { _, selection in
            NotesCaptureCoordinator.shared.editorSelection = selection
        }
        .onChange(of: viewModel.editorSelectionRequest) { _, request in
            guard let request else { return }
            detailEditorSelection = request.range
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                if viewModel.detailMode == .editing {
                    TextField(
                        L10n.localize("notes.detail.title_placeholder", comment: "Note title placeholder"),
                        text: $viewModel.draftTitle
                    )
                    .font(.system(size: 22, weight: .semibold))
                    .textFieldStyle(.plain)
                } else {
                    Text(note.title)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(AppTheme.ColorToken.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                metadataChips
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            headerActions
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
    }

    private var metadataChips: some View {
        HStack(spacing: 6) {
            Text(note.updatedAt.formatted(.dateTime.year().month().day().hour().minute()))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
            chip(label: NotesDetailPresentation.sourceLabel(for: note))
            ForEach(note.tags, id: \.self) { tag in
                chip(label: tag)
            }
        }
    }

    private func chip(label: String) -> some View {
        Text(label)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(AppTheme.ColorToken.secondaryText)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(AppTheme.ColorToken.secondaryText.opacity(0.12))
            )
    }

    @ViewBuilder
    private var headerActions: some View {
        switch viewModel.detailMode {
        case .reading, .continuingDictation:
            HStack(spacing: 6) {
                modalIconButton(
                    systemName: "square.and.pencil",
                    help: L10n.localize("notes.action.edit", comment: "Edit note")
                ) {
                    viewModel.enterEditing()
                }

                modalIconButton(
                    systemName: "doc.on.doc",
                    help: L10n.localize("notes.action.copy", comment: "Copy note")
                ) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(note.bodyMarkdown, forType: .string)
                    viewModel.reportCopied()
                }

                modalIconButton(
                    systemName: "square.and.arrow.down",
                    help: L10n.localize("notes.action.save", comment: "Save note")
                ) {
                    saveMarkdownToFile()
                }

                modalIconButton(
                    systemName: "trash",
                    help: L10n.localize("notes.action.delete", comment: "Delete note action")
                ) {
                    showDeleteConfirmation = true
                }

                modalIconButton(
                    systemName: "xmark",
                    help: L10n.localize("notes.view.close_preview_help", comment: "Close preview tooltip"),
                    action: onClose
                )
            }
        case .editing:
            modalIconButton(
                systemName: "xmark",
                help: L10n.localize("notes.view.close_preview_help", comment: "Close preview tooltip"),
                action: onClose
            )
        }
    }

    private func modalIconButton(
        systemName: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
                .frame(width: 32, height: 32)
                .background(AppTheme.ColorToken.controlBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
                        .stroke(AppTheme.ColorToken.subtleStroke, lineWidth: AppTheme.Border.panelLineWidth)
                )
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func saveMarkdownToFile() {
        do {
            let markdown = try viewModel.exportMarkdown(noteID: note.id)
            let panel = NSSavePanel()
            panel.title = L10n.localize("notes.action.save", comment: "Save note")
            panel.nameFieldStringValue = sanitizedFileName("\(note.title).md")
            panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try markdown.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            viewModel.report(error: error)
        }
    }

    private func sanitizedFileName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:")
        return name.components(separatedBy: invalid).joined(separator: "-")
    }

    // MARK: - Body (scrollable)

    private var bodySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch viewModel.detailMode {
            case .editing:
                CursorTrackingTextEditor(
                    text: $viewModel.draftBodyMarkdown,
                    selection: $detailEditorSelection,
                    isFocused: $detailEditorFocused
                )
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
            case .reading, .continuingDictation:
                ScrollView {
                    Text(markdownBody)
                        .font(.system(size: 15))
                        .lineSpacing(6)
                        .foregroundStyle(AppTheme.ColorToken.primaryText)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 18)
                }

                Divider()
                continueDictationArea
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var continueDictationArea: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text(continuePrompt)
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                Spacer()
                if viewModel.detailMode == .reading {
                    Button {
                        viewModel.enterContinuingDictation()
                    } label: {
                        Label(
                            L10n.localize("notes.action.continue_dictation", comment: "Continue dictation"),
                            systemImage: "mic.badge.plus"
                        )
                    }
                    .buttonStyle(.bordered)
                } else {
                    Label(
                        L10n.localize("notes.detail.continuing_status", comment: "Continuing dictation status"),
                        systemImage: "waveform"
                    )
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.ColorToken.accentDark)
                }
            }

            HStack(spacing: 8) {
                chip(label: NotesDetailPresentation.sourceLabel(for: note))
                if note.tags.isEmpty {
                    chip(label: L10n.localize("notes.detail.untagged", comment: "Untagged note"))
                } else {
                    ForEach(note.tags, id: \.self) { tag in
                        chip(label: tag)
                    }
                }
                chip(label: L10n.localize("notes.detail.manual_save", comment: "Manual save mode"))
            }
        }
    }

    private var continuePrompt: String {
        viewModel.detailMode == .continuingDictation
            ? L10n.localize("notes.detail.continuing_dictation_hint", comment: "Continuing dictation hint")
            : L10n.localize("notes.detail.continue_prompt", comment: "Continue note prompt")
    }

    private var markdownBody: AttributedString {
        (try? AttributedString(markdown: note.bodyMarkdown)) ?? AttributedString(note.bodyMarkdown)
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        HStack {
            if viewModel.detailMode == .editing {
                Text(L10n.localize(
                    "notes.detail.editing_status",
                    comment: "Editing status"
                ))
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
            } else if viewModel.detailMode == .continuingDictation {
                Text(L10n.localize(
                    "notes.detail.continuing_status",
                    comment: "Continuing dictation status"
                ))
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.ColorToken.accentDark)
            } else {
                Text(L10n.localize(
                    "notes.detail.reading_status",
                    comment: "Saved status"
                ))
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
            }
            Spacer()
            footerPrimaryAction
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var footerPrimaryAction: some View {
        switch viewModel.detailMode {
        case .editing:
            Button {
                viewModel.cancelEditing()
            } label: {
                Text(L10n.localize("notes.action.cancel_edit", comment: "Cancel edit"))
            }
            .buttonStyle(.bordered)
            Button {
                do {
                    try viewModel.saveDraft()
                } catch {
                    viewModel.report(error: error)
                }
            } label: {
                Text(L10n.localize("notes.action.save", comment: "Save note"))
            }
            .buttonStyle(.borderedProminent)
        case .continuingDictation:
            Button {
                viewModel.exitContinuingDictation()
            } label: {
                Text(L10n.localize("notes.action.finish_continuing", comment: "Finish continuing dictation"))
            }
            .buttonStyle(.borderedProminent)
        case .reading:
            Button(action: onClose) {
                Text(L10n.localize("notes.action.done", comment: "Done"))
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

private struct EscapeKeyHandler: NSViewRepresentable {
    let onEscape: () -> Void

    func makeNSView(context: Context) -> EscapeCatchingView {
        EscapeCatchingView(onEscape: onEscape)
    }

    func updateNSView(_ nsView: EscapeCatchingView, context: Context) {
        nsView.onEscape = onEscape
        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

private final class EscapeCatchingView: NSView {
    var onEscape: () -> Void

    init(onEscape: @escaping () -> Void) {
        self.onEscape = onEscape
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape()
        } else {
            super.keyDown(with: event)
        }
    }
}

/// 可测试的笔记详情 presentation 辅助。
enum NotesDetailPresentation {
    static func sourceLabel(for note: NoteRecord) -> String {
        switch note.sourceType {
        case "fileTranscription":
            return L10n.localize("notes.source.file_transcription", comment: "File transcription source")
        case "history":
            return L10n.localize("notes.source.history", comment: "History source")
        case "manual":
            return L10n.localize("notes.source.manual", comment: "Manual source")
        default:
            return note.sourceType
        }
    }
}

struct CursorTrackingTextEditor: NSViewRepresentable {
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
        let clampedSelection = Self.clamped(selection, in: text)
        textView.setSelectedRange(clampedSelection)
        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.lastSelectionFromBinding = clampedSelection
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let clampedSelection = Self.clamped(selection, in: text)
        let textChanged = textView.string != text
        let selectionChanged = context.coordinator.lastSelectionFromBinding != clampedSelection
        if textChanged || (selectionChanged && textView.selectedRange() != clampedSelection) {
            context.coordinator.performProgrammaticUpdate {
                if textView.string != text {
                    textView.string = text
                }
                if selectionChanged && textView.selectedRange() != clampedSelection {
                    textView.setSelectedRange(clampedSelection)
                }
            }
        }
        context.coordinator.lastSelectionFromBinding = clampedSelection
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
        var lastSelectionFromBinding: NSRange?
        private var isPerformingProgrammaticUpdate = false

        init(parent: CursorTrackingTextEditor) {
            self.parent = parent
        }

        func performProgrammaticUpdate(_ update: () -> Void) {
            isPerformingProgrammaticUpdate = true
            defer { isPerformingProgrammaticUpdate = false }
            update()
        }

        func textDidBeginEditing(_ notification: Notification) {
            guard !isPerformingProgrammaticUpdate else { return }
            parent.isFocused = true
        }

        func textDidEndEditing(_ notification: Notification) {
            guard !isPerformingProgrammaticUpdate else { return }
            parent.isFocused = false
        }

        func textDidChange(_ notification: Notification) {
            guard !isPerformingProgrammaticUpdate else { return }
            guard let textView else { return }
            parent.text = textView.string
            parent.selection = textView.selectedRange()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isPerformingProgrammaticUpdate else { return }
            guard let textView else { return }
            parent.selection = textView.selectedRange()
            parent.isFocused = textView.window?.firstResponder === textView
        }
    }
}
