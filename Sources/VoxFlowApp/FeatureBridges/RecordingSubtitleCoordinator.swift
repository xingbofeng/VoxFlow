import Foundation

/// 字幕协调器：集中管理字幕状态机、权限错误、服务调用和 repository 更新。
///
/// UI 层（HUD、详情页、编辑确认界面）只通过协调器发起动作并展示状态，
/// 不直接操作 Speech 或 AVFoundation。
///
/// 状态机：`none → generating → draftReady → burning → burned`，任意阶段失败进入 `failed`。
/// 取消生成回到上一个稳定态（有草稿则 `draftReady`，否则 `none`）；取消烧录回到 `draftReady`。
@MainActor
final class RecordingSubtitleCoordinator {
    private let repository: any MediaRecordRepository
    private let draftStore: RecordingSubtitleDraftStore
    private let transcriber: any SystemRecordingSubtitleTranscriber
    private let burner: any RecordingSubtitleBurner
    private let paths: ApplicationSupportPaths
    private let clock: any AppClock
    private let onStateChange: (String) -> Void
    private let onDraftReady: (String) -> Void
    private let onBurnedVideoReady: (URL) -> Void

    private var generationTasks: [String: Task<Void, Never>] = [:]
    private var burnTasks: [String: Task<Void, Never>] = [:]

    init(
        repository: any MediaRecordRepository,
        draftStore: RecordingSubtitleDraftStore,
        transcriber: any SystemRecordingSubtitleTranscriber,
        burner: any RecordingSubtitleBurner,
        paths: ApplicationSupportPaths,
        clock: any AppClock,
        onStateChange: @escaping (String) -> Void = { _ in },
        onDraftReady: @escaping (String) -> Void = { _ in },
        onBurnedVideoReady: @escaping (URL) -> Void = { _ in }
    ) {
        self.repository = repository
        self.draftStore = draftStore
        self.transcriber = transcriber
        self.burner = burner
        self.paths = paths
        self.clock = clock
        self.onStateChange = onStateChange
        self.onDraftReady = onDraftReady
        self.onBurnedVideoReady = onBurnedVideoReady
    }

    // MARK: - 状态查询

    /// 当前字幕状态。
    func currentState(for recordID: String) -> RecordingSubtitleState {
        guard let record = try? repository.record(id: recordID) else {
            return .none
        }
        return RecordingSubtitleState(
            status: record.subtitleStatus,
            draftPath: record.subtitleDraftPath,
            srtPath: record.subtitleSrtPath,
            subtitledVideoPath: record.subtitledVideoPath,
            errorMessage: record.subtitleErrorMessage,
            updatedAt: record.subtitleUpdatedAt
        )
    }

    /// 仅麦克风录屏可添加字幕。
    func canAddSubtitle(_ record: MediaRecord) -> Bool {
        record.mediaType == .screenRecording && record.audioMode == .microphone
    }

    // MARK: - 入口：添加字幕

    /// HUD/详情页点击 `添加字幕` 时调用，按当前状态选择动作。
    func addSubtitle(recordID: String) {
        let state = currentState(for: recordID)
        switch state.status {
        case .none, .failed:
            startGeneration(recordID: recordID)
        case .draftReady:
            onDraftReady(recordID)
        case .generating, .burning:
            // 进行中，忽略重复入口。
            break
        case .burned:
            // 已烧录，由详情页/HUD 提供打开带字幕视频入口。
            break
        }
    }

    // MARK: - 生成

    func startGeneration(recordID: String) {
        generationTasks[recordID]?.cancel()
        generationTasks[recordID] = nil
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performGeneration(recordID: recordID)
        }
        generationTasks[recordID] = task
    }

    func cancelGeneration(recordID: String) async {
        if let task = generationTasks[recordID] {
            task.cancel()
            await task.value
            generationTasks[recordID] = nil
        }
        // 取消后恢复到上一个稳定态。
        restoreStableStateAfterGenerationCancel(recordID: recordID)
    }

    func retryGeneration(recordID: String) {
        startGeneration(recordID: recordID)
    }

    private func performGeneration(recordID: String) async {
        guard let record = try? repository.record(id: recordID) else { return }
        // 5.3 仅麦克风录屏进入生成；否则不修改状态、不调用服务。
        guard canAddSubtitle(record) else {
            onStateChange(recordID)
            return
        }
        guard let videoPath = record.videoPath else {
            await failGeneration(recordID: recordID, message: "录屏视频文件缺失")
            return
        }

        setState(
            recordID: recordID,
            status: .generating,
            draftPath: nil,
            srtPath: nil,
            subtitledVideoPath: nil,
            errorMessage: nil
        )

        do {
            let result = try await transcriber.transcribe(
                videoURL: URL(fileURLWithPath: videoPath),
                audioMode: record.audioMode
            )
            let now = clock.now
            let draft = RecordingSubtitleDraft(
                mediaRecordID: recordID,
                sourceVideoPath: videoPath,
                segments: result.segments,
                createdAt: now,
                updatedAt: now
            )
            try draftStore.save(draft)
            let srtURL = paths.recordingSubtitleSRTURL(forID: recordID)
            try RecordingSubtitleSRTExporter.export(draft: draft, to: srtURL)
            // 3.6 生成成功：保存草稿 JSON、导出 SRT、状态 draftReady，不自动烧录。
            setState(
                recordID: recordID,
                status: .draftReady,
                draftPath: draftStore.draftURL(for: recordID).path,
                srtPath: srtURL.path,
                subtitledVideoPath: nil,
                errorMessage: nil
            )
            onDraftReady(recordID)
        } catch is CancellationError {
            // 3.8 取消生成：恢复上一个稳定态。
            restoreStableStateAfterGenerationCancel(recordID: recordID)
        } catch {
            // 3.7 生成失败：状态 failed，保存错误信息，原视频不动。
            await failGeneration(recordID: recordID, message: error.localizedDescription)
        }
    }

    private func failGeneration(recordID: String, message: String) async {
        setState(
            recordID: recordID,
            status: .failed,
            draftPath: nil,
            srtPath: nil,
            subtitledVideoPath: nil,
            errorMessage: message
        )
    }

    private func restoreStableStateAfterGenerationCancel(recordID: String) {
        let draftExists = (try? draftStore.load(mediaID: recordID)) != nil
        let existing = currentState(for: recordID)
        if draftExists {
            setState(
                recordID: recordID,
                status: .draftReady,
                draftPath: existing.draftPath ?? draftStore.draftURL(for: recordID).path,
                srtPath: existing.srtPath,
                subtitledVideoPath: existing.subtitledVideoPath,
                errorMessage: nil
            )
        } else {
            setState(
                recordID: recordID,
                status: .none,
                draftPath: nil,
                srtPath: nil,
                subtitledVideoPath: nil,
                errorMessage: nil
            )
        }
    }

    // MARK: - 烧录

    func startBurn(recordID: String) {
        burnTasks[recordID]?.cancel()
        burnTasks[recordID] = nil
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performBurn(recordID: recordID)
        }
        burnTasks[recordID] = task
    }

    func cancelBurn(recordID: String) async {
        if let task = burnTasks[recordID] {
            task.cancel()
            await task.value
            burnTasks[recordID] = nil
        }
        restoreDraftReadyAfterBurnCancel(recordID: recordID)
    }

    func retryBurn(recordID: String) {
        startBurn(recordID: recordID)
    }

    /// 直接打开字幕编辑确认界面（详情页"查看/编辑字幕"使用）。
    func openEditor(recordID: String) {
        onDraftReady(recordID)
    }

    /// 取消该记录进行中的生成/烧录任务（删除录屏时调用）。
    func cancelInFlightTasks(recordID: String) {
        generationTasks[recordID]?.cancel()
        generationTasks[recordID] = nil
        burnTasks[recordID]?.cancel()
        burnTasks[recordID] = nil
    }

    private func performBurn(recordID: String) async {
        guard let record = try? repository.record(id: recordID) else { return }
        guard let draft = try? draftStore.load(mediaID: recordID) else {
            await failBurn(recordID: recordID, message: "字幕草稿缺失")
            return
        }
        guard let videoPath = record.videoPath else {
            await failBurn(recordID: recordID, message: "录屏视频文件缺失")
            return
        }
        let outputURL = paths.recordingSubtitledVideoURL(forID: recordID)

        // 4.5 烧录开始：状态 burning。
        setState(
            recordID: recordID,
            status: .burning,
            draftPath: draftStore.draftURL(for: recordID).path,
            srtPath: paths.recordingSubtitleSRTURL(forID: recordID).path,
            subtitledVideoPath: nil,
            errorMessage: nil
        )

        do {
            // 4.2/4.6 烧录：生成新 mp4，原视频路径不变。
            let result = try await burner.burn(
                sourceVideoURL: URL(fileURLWithPath: videoPath),
                draft: draft,
                outputURL: outputURL
            )
            let existing = currentState(for: recordID)
            setState(
                recordID: recordID,
                status: .burned,
                draftPath: existing.draftPath,
                srtPath: existing.srtPath,
                subtitledVideoPath: result.outputURL.path,
                errorMessage: nil
            )
            // 5.5 烧录成功后通知 UI 刷新，优先展示带字幕视频。
            onStateChange(recordID)
            onBurnedVideoReady(result.outputURL)
        } catch is CancellationError {
            // 4.8 取消烧录：删除半成品，保留草稿，恢复 draftReady。
            try? FileManager.default.removeItem(at: outputURL)
            restoreDraftReadyAfterBurnCancel(recordID: recordID)
        } catch {
            // 4.7 烧录失败：删除半成品，保留草稿，状态 failed。
            try? FileManager.default.removeItem(at: outputURL)
            await failBurn(recordID: recordID, message: error.localizedDescription)
        }
    }

    private func failBurn(recordID: String, message: String) async {
        let existing = currentState(for: recordID)
        setState(
            recordID: recordID,
            status: .failed,
            draftPath: existing.draftPath,
            srtPath: existing.srtPath,
            subtitledVideoPath: nil,
            errorMessage: message
        )
    }

    private func restoreDraftReadyAfterBurnCancel(recordID: String) {
        let existing = currentState(for: recordID)
        setState(
            recordID: recordID,
            status: .draftReady,
            draftPath: existing.draftPath ?? draftStore.draftURL(for: recordID).path,
            srtPath: existing.srtPath,
            subtitledVideoPath: nil,
            errorMessage: nil
        )
    }

    // MARK: - 草稿读写（编辑确认界面使用）

    func loadDraft(recordID: String) throws -> RecordingSubtitleDraft? {
        try draftStore.load(mediaID: recordID)
    }

    func saveDraft(_ draft: RecordingSubtitleDraft) throws {
        try draftStore.save(draft)
        let existing = currentState(for: draft.mediaRecordID)
        setState(
            recordID: draft.mediaRecordID,
            status: existing.status == .none ? .draftReady : existing.status,
            draftPath: draftStore.draftURL(for: draft.mediaRecordID).path,
            srtPath: existing.srtPath,
            subtitledVideoPath: existing.subtitledVideoPath,
            errorMessage: nil
        )
        // 同步重新导出 SRT，保持外部兼容文件最新。
        try? RecordingSubtitleSRTExporter.export(
            draft: draft,
            to: paths.recordingSubtitleSRTURL(forID: draft.mediaRecordID)
        )
    }

    // MARK: - 状态写入

    private func setState(
        recordID: String,
        status: RecordingSubtitleStatus,
        draftPath: String?,
        srtPath: String?,
        subtitledVideoPath: String?,
        errorMessage: String?
    ) {
        let state = RecordingSubtitleState(
            status: status,
            draftPath: draftPath,
            srtPath: srtPath,
            subtitledVideoPath: subtitledVideoPath,
            errorMessage: errorMessage,
            updatedAt: clock.now
        )
        try? repository.updateSubtitleState(id: recordID, state: state, updatedAt: clock.now)
        onStateChange(recordID)
    }
}
