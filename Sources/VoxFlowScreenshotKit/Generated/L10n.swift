// swiftlint:disable all
// Generated using SwiftGen — https://github.com/SwiftGen/SwiftGen

import Foundation

// swiftlint:disable superfluous_disable_command file_length implicit_return prefer_self_in_static_references

// MARK: - Strings

// swiftlint:disable explicit_type_interface function_parameter_count identifier_name line_length
// swiftlint:disable nesting type_body_length type_name vertical_whitespace_opening_braces
internal enum ScreenshotL10n {
  internal enum Localizable {
    internal enum Agent {
      internal enum Helper {
        /// Auto-filled localization coverage
        internal static func errorCommandConflictFormat(_ p1: Any) -> String {
          return ScreenshotL10n.tr("Localizable", "agent.helper.error_command_conflict_format", String(describing: p1), fallback: "Command conflicts with an existing helper: %@")
        }
        /// Required helper component is missing: %@
        internal static func errorComponentMissingFormat(_ p1: Any) -> String {
          return ScreenshotL10n.tr("Localizable", "agent.helper.error_component_missing_format", String(describing: p1), fallback: "Required helper component is missing: %@")
        }
        /// The helper returned an invalid response.
        internal static let errorInvalidResponse = ScreenshotL10n.tr("Localizable", "agent.helper.error_invalid_response", fallback: "The helper returned an invalid response.")
        /// The helper request is too large.
        internal static let errorRequestTooLarge = ScreenshotL10n.tr("Localizable", "agent.helper.error_request_too_large", fallback: "The helper request is too large.")
        /// Helper shim is missing: %@
        internal static func errorShimMissingFormat(_ p1: Any) -> String {
          return ScreenshotL10n.tr("Localizable", "agent.helper.error_shim_missing_format", String(describing: p1), fallback: "Helper shim is missing: %@")
        }
        /// The helper request timed out.
        internal static let errorTimeout = ScreenshotL10n.tr("Localizable", "agent.helper.error_timeout", fallback: "The helper request timed out.")
      }
      internal enum Session {
        internal enum Status {
          /// ===== Localization migration coverage =====
          internal static let exited = ScreenshotL10n.tr("Localizable", "agent.session.status.exited", fallback: "Exited")
          /// Online
          internal static let online = ScreenshotL10n.tr("Localizable", "agent.session.status.online", fallback: "Online")
          /// Stale
          internal static let stale = ScreenshotL10n.tr("Localizable", "agent.session.status.stale", fallback: "Stale")
        }
      }
    }
    internal enum AgentDispatch {
      internal enum Error {
        /// Multiple matching task assistants were found.
        internal static let agentAmbiguous = ScreenshotL10n.tr("Localizable", "agent_dispatch.error.agent_ambiguous", fallback: "Multiple matching task assistants were found.")
        /// The task assistant has exited.
        internal static let agentExited = ScreenshotL10n.tr("Localizable", "agent_dispatch.error.agent_exited", fallback: "The task assistant has exited.")
        /// The task assistant input channel is unavailable.
        internal static let agentInputChannelMissing = ScreenshotL10n.tr("Localizable", "agent_dispatch.error.agent_input_channel_missing", fallback: "The task assistant input channel is unavailable.")
        /// No matching task assistant was found.
        internal static let agentNotFound = ScreenshotL10n.tr("Localizable", "agent_dispatch.error.agent_not_found", fallback: "No matching task assistant was found.")
        /// The task assistant session is stale.
        internal static let agentStale = ScreenshotL10n.tr("Localizable", "agent_dispatch.error.agent_stale", fallback: "The task assistant session is stale.")
        /// Sending was cancelled.
        internal static let cancelledSend = ScreenshotL10n.tr("Localizable", "agent_dispatch.error.cancelled_send", fallback: "Sending was cancelled.")
        /// No clear task assistant found
        internal static let noClearTarget = ScreenshotL10n.tr("Localizable", "agent_dispatch.error.no_clear_target", fallback: "No clear task assistant found")
        /// No command to send.
        internal static let noCommandToSend = ScreenshotL10n.tr("Localizable", "agent_dispatch.error.no_command_to_send", fallback: "No command to send.")
        /// The target task assistant is unavailable.
        internal static let targetUnavailable = ScreenshotL10n.tr("Localizable", "agent_dispatch.error.target_unavailable", fallback: "The target task assistant is unavailable.")
        /// Failed to write to the task assistant.
        internal static let writeFailed = ScreenshotL10n.tr("Localizable", "agent_dispatch.error.write_failed", fallback: "Failed to write to the task assistant.")
      }
    }
    internal enum App {
      internal enum AgentDispatch {
        /// ===== App-wide copy =====
        internal static let failure = ScreenshotL10n.tr("Localizable", "app.agent_dispatch.failure", fallback: "Unable to dispatch the AI assistant request. Please try again.")
      }
      internal enum ClipboardOcr {
        internal enum Error {
          /// OCR operation cancelled.
          internal static let cancelled = ScreenshotL10n.tr("Localizable", "app.clipboard_ocr.error.cancelled", fallback: "OCR operation cancelled.")
          /// ===== App =====
          internal static let disabled = ScreenshotL10n.tr("Localizable", "app.clipboard_ocr.error.disabled", fallback: "Clipboard image OCR is disabled.")
          /// No recognizable image found in clipboard.
          internal static let noImage = ScreenshotL10n.tr("Localizable", "app.clipboard_ocr.error.no_image", fallback: "No recognizable image found in clipboard.")
          /// No text recognized from the image.
          internal static let noText = ScreenshotL10n.tr("Localizable", "app.clipboard_ocr.error.no_text", fallback: "No text recognized from the image.")
        }
      }
      internal enum Dictation {
        /// Please configure an AI model first, then restart VoxFlow and try again.
        internal static let setupAiModelRequired = ScreenshotL10n.tr("Localizable", "app.dictation.setup_ai_model_required", fallback: "Please configure an AI model first, then restart VoxFlow and try again.")
      }
      internal enum Learning {
        /// Failed to undo the last correction.
        internal static let undoFailed = ScreenshotL10n.tr("Localizable", "app.learning.undo_failed", fallback: "Failed to undo the last correction.")
        /// Undo applied successfully.
        internal static let undoSuccess = ScreenshotL10n.tr("Localizable", "app.learning.undo_success", fallback: "Undo applied successfully.")
        /// No changes to undo.
        internal static let undoUnchanged = ScreenshotL10n.tr("Localizable", "app.learning.undo_unchanged", fallback: "No changes to undo.")
      }
      internal enum MainWindow {
        /// ===== Window and settings =====
        internal static let title = ScreenshotL10n.tr("Localizable", "app.main_window.title", fallback: "VoxFlow")
      }
      internal enum NotesRecording {
        internal enum Error {
          /// No content was recognized, please retry.
          internal static let noContent = ScreenshotL10n.tr("Localizable", "app.notes_recording.error.no_content", fallback: "No content was recognized, please retry.")
          /// The selected dictation language is not supported: %@.
          internal static func unsupportedLanguageFormat(_ p1: Any) -> String {
            return ScreenshotL10n.tr("Localizable", "app.notes_recording.error.unsupported_language_format", String(describing: p1), fallback: "The selected dictation language is not supported: %@.")
          }
        }
      }
      internal enum Output {
        /// Input failed. Please retry. If this keeps happening, check permissions.
        internal static let inputFailed = ScreenshotL10n.tr("Localizable", "app.output.input_failed", fallback: "Input failed. Please retry. If this keeps happening, check permissions.")
      }
      internal enum Paths {
        /// Unable to locate the Application Support directory.
        internal static let applicationSupportUnavailable = ScreenshotL10n.tr("Localizable", "app.paths.application_support_unavailable", fallback: "Unable to locate the Application Support directory.")
      }
      internal enum Permissions {
        /// VoxFlow needs Accessibility permission to monitor and trigger global shortcuts.
        internal static let accessibilitySubtitleFormat = ScreenshotL10n.tr("Localizable", "app.permissions.accessibility_subtitle_format", fallback: "VoxFlow needs Accessibility permission to monitor and trigger global shortcuts.")
        /// Accessibility access
        internal static let accessibilityTitle = ScreenshotL10n.tr("Localizable", "app.permissions.accessibility_title", fallback: "Accessibility access")
        /// VoxFlow permissions are managed in Privacy & Security.
        internal static let checkSubtitleFormat = ScreenshotL10n.tr("Localizable", "app.permissions.check_subtitle_format", fallback: "VoxFlow permissions are managed in Privacy & Security.")
        /// Permission Status
        internal static let checkTitle = ScreenshotL10n.tr("Localizable", "app.permissions.check_title", fallback: "Permission Status")
      }
      internal enum Update {
        /// Local debug mock update used for verifying the update prompt flow.
        internal static let mockReleaseNotes = ScreenshotL10n.tr("Localizable", "app.update.mock_release_notes", fallback: "Local debug mock update used for verifying the update prompt flow.")
      }
      internal enum Workflow {
        /// Capture cancelled.
        internal static let captureCancelled = ScreenshotL10n.tr("Localizable", "app.workflow.capture_cancelled", fallback: "Capture cancelled.")
        /// A workflow is already running. Please wait a moment.
        internal static let inProgress = ScreenshotL10n.tr("Localizable", "app.workflow.in_progress", fallback: "A workflow is already running. Please wait a moment.")
        /// Unable to start screen recording:
        internal static let recordingStartFailed = ScreenshotL10n.tr("Localizable", "app.workflow.recording_start_failed", fallback: "Unable to start screen recording:")
        /// Failed to save recording:
        internal static let screenRecordingSaveFailed = ScreenshotL10n.tr("Localizable", "app.workflow.screen_recording_save_failed", fallback: "Failed to save recording:")
        /// Screen recording saved.
        internal static let screenRecordingSaved = ScreenshotL10n.tr("Localizable", "app.workflow.screen_recording_saved", fallback: "Screen recording saved.")
        /// Screenshot OCR is processing.
        internal static let screenshotOcrProcessing = ScreenshotL10n.tr("Localizable", "app.workflow.screenshot_ocr_processing", fallback: "Screenshot OCR is processing.")
        /// Translation completed.
        internal static let translationCompleted = ScreenshotL10n.tr("Localizable", "app.workflow.translation_completed", fallback: "Translation completed.")
      }
    }
    internal enum Asr {
      internal enum Error {
        /// API key is not configured. Please set it up in Settings.
        internal static let apiKeyMissing = ScreenshotL10n.tr("Localizable", "asr.error.api_key_missing", fallback: "API key is not configured. Please set it up in Settings.")
        /// Failed to read the audio file.
        internal static let audioReadFailed = ScreenshotL10n.tr("Localizable", "asr.error.audio_read_failed", fallback: "Failed to read the audio file.")
        /// Cloud ASR service failed. Please try again later.
        internal static let cloudServiceFailed = ScreenshotL10n.tr("Localizable", "asr.error.cloud_service_failed", fallback: "Cloud ASR service failed. Please try again later.")
        /// Recognition service timed out. Please try again.
        internal static let connectionTimeout = ScreenshotL10n.tr("Localizable", "asr.error.connection_timeout", fallback: "Recognition service timed out. Please try again.")
        /// Insufficient disk space to complete the download.
        internal static let diskSpace = ScreenshotL10n.tr("Localizable", "asr.error.disk_space", fallback: "Insufficient disk space to complete the download.")
        /// Download cancelled.
        internal static let downloadCancelled = ScreenshotL10n.tr("Localizable", "asr.error.download_cancelled", fallback: "Download cancelled.")
        /// Download interrupted. Please check your network and try again.
        internal static let downloadInterrupted = ScreenshotL10n.tr("Localizable", "asr.error.download_interrupted", fallback: "Download interrupted. Please check your network and try again.")
        /// Download paused. You can resume later.
        internal static let downloadPaused = ScreenshotL10n.tr("Localizable", "asr.error.download_paused", fallback: "Download paused. You can resume later.")
        /// Download link is insecure. Aborted.
        internal static let downloadUrlInsecure = ScreenshotL10n.tr("Localizable", "asr.error.download_url_insecure", fallback: "Download link is insecure. Aborted.")
        /// No transcription result was produced. Please try again.
        internal static let emptyTranscript = ScreenshotL10n.tr("Localizable", "asr.error.empty_transcript", fallback: "No transcription result was produced. Please try again.")
        /// This device does not support the selected ASR engine.
        internal static let hardwareUnsupported = ScreenshotL10n.tr("Localizable", "asr.error.hardware_unsupported", fallback: "This device does not support the selected ASR engine.")
        /// Diagnosing connection…
        internal static let healthCheck = ScreenshotL10n.tr("Localizable", "asr.error.health_check", fallback: "Diagnosing connection…")
        /// Connection OK.
        internal static let healthCheckOk = ScreenshotL10n.tr("Localizable", "asr.error.health_check_ok", fallback: "Connection OK.")
        /// ASR service returned an invalid response. Please try again.
        internal static let invalidResponse = ScreenshotL10n.tr("Localizable", "asr.error.invalid_response", fallback: "ASR service returned an invalid response. Please try again.")
        /// ASR model file is corrupted. Please re-download.
        internal static let modelCorrupt = ScreenshotL10n.tr("Localizable", "asr.error.model_corrupt", fallback: "ASR model file is corrupted. Please re-download.")
        /// ===== ASR Provider error message mapping =====
        internal static let modelNotInstalled = ScreenshotL10n.tr("Localizable", "asr.error.model_not_installed", fallback: "ASR model is not installed. Please download it in Settings.")
        /// The selected recognition language is not supported.
        internal static let unsupportedLanguage = ScreenshotL10n.tr("Localizable", "asr.error.unsupported_language", fallback: "The selected recognition language is not supported.")
      }
      internal enum Provider {
        /// API key saved
        internal static let apiKeySaved = ScreenshotL10n.tr("Localizable", "asr.provider.api_key_saved", fallback: "API key saved")
        /// Collapse configuration
        internal static let collapseConfiguration = ScreenshotL10n.tr("Localizable", "asr.provider.collapse_configuration", fallback: "Collapse configuration")
        /// Credentials saved
        internal static let credentialsSaved = ScreenshotL10n.tr("Localizable", "asr.provider.credentials_saved", fallback: "Credentials saved")
        /// Current
        internal static let currentBadge = ScreenshotL10n.tr("Localizable", "asr.provider.current_badge", fallback: "Current")
        /// Delete API Key
        internal static let deleteApiKey = ScreenshotL10n.tr("Localizable", "asr.provider.delete_api_key", fallback: "Delete API Key")
        /// Delete Credentials
        internal static let deleteCredentials = ScreenshotL10n.tr("Localizable", "asr.provider.delete_credentials", fallback: "Delete Credentials")
        /// Expand configuration
        internal static let expandConfiguration = ScreenshotL10n.tr("Localizable", "asr.provider.expand_configuration", fallback: "Expand configuration")
        /// Hide API key
        internal static let hideApiKey = ScreenshotL10n.tr("Localizable", "asr.provider.hide_api_key", fallback: "Hide API key")
        /// Model
        internal static let model = ScreenshotL10n.tr("Localizable", "asr.provider.model", fallback: "Model")
        /// Precision
        internal static let precision = ScreenshotL10n.tr("Localizable", "asr.provider.precision", fallback: "Precision")
        /// Save Configuration
        internal static let saveConfiguration = ScreenshotL10n.tr("Localizable", "asr.provider.save_configuration", fallback: "Save Configuration")
        /// Select %@
        internal static func selectAccessibilityFormat(_ p1: Any) -> String {
          return ScreenshotL10n.tr("Localizable", "asr.provider.select_accessibility_format", String(describing: p1), fallback: "Select %@")
        }
        /// Show API key
        internal static let showApiKey = ScreenshotL10n.tr("Localizable", "asr.provider.show_api_key", fallback: "Show API key")
        /// Test Connection
        internal static let testConnection = ScreenshotL10n.tr("Localizable", "asr.provider.test_connection", fallback: "Test Connection")
        /// Testing...
        internal static let testingConnection = ScreenshotL10n.tr("Localizable", "asr.provider.testing_connection", fallback: "Testing...")
        /// ASR providers
        internal static let title = ScreenshotL10n.tr("Localizable", "asr.provider.title", fallback: "Dictation Models")
        internal enum Aliyun {
          /// Bailian API key
          internal static let apiKeyPlaceholder = ScreenshotL10n.tr("Localizable", "asr.provider.aliyun.api_key_placeholder", fallback: "Bailian API key")
          /// Alibaba Cloud Bailian Configuration
          internal static let configurationTitle = ScreenshotL10n.tr("Localizable", "asr.provider.aliyun.configuration_title", fallback: "Alibaba Cloud Bailian Configuration")
          /// Use DashScope real-time ASR over WebSocket. The endpoint is wss://dashscope.aliyuncs.com/api-ws/v1/inference and authentication uses Authorization: Bearer with the API key.
          internal static let description = ScreenshotL10n.tr("Localizable", "asr.provider.aliyun.description", fallback: "Use DashScope real-time ASR over WebSocket. The endpoint is wss://dashscope.aliyuncs.com/api-ws/v1/inference and authentication uses Authorization: Bearer with the API key.")
          /// Audio is sent to Alibaba Cloud Bailian. The API key is stored in local credentials and can be shown or hidden with the eye button. The recommended ASR model is used by default.
          internal static let privacyNote = ScreenshotL10n.tr("Localizable", "asr.provider.aliyun.privacy_note", fallback: "Audio is sent to Alibaba Cloud Bailian. The API key is stored in local credentials and can be shown or hidden with the eye button. The recommended ASR model is used by default.")
        }
        internal enum Groq {
          /// Groq API key
          internal static let apiKeyPlaceholder = ScreenshotL10n.tr("Localizable", "asr.provider.groq.api_key_placeholder", fallback: "Groq API key")
          /// Groq Configuration
          internal static let configurationTitle = ScreenshotL10n.tr("Localizable", "asr.provider.groq.configuration_title", fallback: "Groq Configuration")
          /// Audio is sent to Groq. The API key is stored in local credentials and can be shown or hidden with the eye button.
          internal static let privacyNote = ScreenshotL10n.tr("Localizable", "asr.provider.groq.privacy_note", fallback: "Audio is sent to Groq. The API key is stored in local credentials and can be shown or hidden with the eye button.")
        }
        internal enum LocalModel {
          /// Download Model
          internal static let actionDownload = ScreenshotL10n.tr("Localizable", "asr.provider.local_model.action_download", fallback: "Download Model")
          /// Downloading
          internal static let actionDownloading = ScreenshotL10n.tr("Localizable", "asr.provider.local_model.action_downloading", fallback: "Downloading")
          /// Repair Model
          internal static let actionRepair = ScreenshotL10n.tr("Localizable", "asr.provider.local_model.action_repair", fallback: "Repair Model")
          /// Repairing
          internal static let actionRepairing = ScreenshotL10n.tr("Localizable", "asr.provider.local_model.action_repairing", fallback: "Repairing")
          /// Resume Download
          internal static let actionResume = ScreenshotL10n.tr("Localizable", "asr.provider.local_model.action_resume", fallback: "Resume Download")
          /// Clean Model
          internal static let clean = ScreenshotL10n.tr("Localizable", "asr.provider.local_model.clean", fallback: "Clean Model")
          /// Delete Model
          internal static let delete = ScreenshotL10n.tr("Localizable", "asr.provider.local_model.delete", fallback: "Delete Model")
          /// Model Size
          internal static let sizeLabel = ScreenshotL10n.tr("Localizable", "asr.provider.local_model.size_label", fallback: "Model Size")
          /// Downloading required files
          internal static let statusDownloading = ScreenshotL10n.tr("Localizable", "asr.provider.local_model.status_downloading", fallback: "Downloading required files")
          /// Model Status
          internal static let statusLabel = ScreenshotL10n.tr("Localizable", "asr.provider.local_model.status_label", fallback: "Model Status")
          /// Not downloaded
          internal static let statusNotDownloaded = ScreenshotL10n.tr("Localizable", "asr.provider.local_model.status_not_downloaded", fallback: "Not downloaded")
          /// Ready to use
          internal static let statusReady = ScreenshotL10n.tr("Localizable", "asr.provider.local_model.status_ready", fallback: "Ready to use")
          /// Repair needed
          internal static let statusRepairNeeded = ScreenshotL10n.tr("Localizable", "asr.provider.local_model.status_repair_needed", fallback: "Repair needed")
          /// Download can resume
          internal static let statusResume = ScreenshotL10n.tr("Localizable", "asr.provider.local_model.status_resume", fallback: "Download can resume")
          /// Unavailable
          internal static let statusUnavailable = ScreenshotL10n.tr("Localizable", "asr.provider.local_model.status_unavailable", fallback: "Unavailable")
        }
        internal enum Scope {
          /// All
          internal static let all = ScreenshotL10n.tr("Localizable", "asr.provider.scope.all", fallback: "All")
          /// Offline
          internal static let offline = ScreenshotL10n.tr("Localizable", "asr.provider.scope.offline", fallback: "Offline")
          /// Online
          internal static let online = ScreenshotL10n.tr("Localizable", "asr.provider.scope.online", fallback: "Online")
        }
        internal enum Tencent {
          /// App ID
          internal static let appId = ScreenshotL10n.tr("Localizable", "asr.provider.tencent.app_id", fallback: "App ID")
          /// Tencent Cloud Configuration
          internal static let configurationTitle = ScreenshotL10n.tr("Localizable", "asr.provider.tencent.configuration_title", fallback: "Tencent Cloud Configuration")
          /// Use Tencent Cloud real-time streaming ASR over WebSocket. Get the app ID, secret ID, and secret key from the Tencent Cloud console.
          internal static let description = ScreenshotL10n.tr("Localizable", "asr.provider.tencent.description", fallback: "Use Tencent Cloud real-time streaming ASR over WebSocket. Get the app ID, secret ID, and secret key from the Tencent Cloud console.")
          /// Hide Tencent Cloud credentials
          internal static let hideCredentials = ScreenshotL10n.tr("Localizable", "asr.provider.tencent.hide_credentials", fallback: "Hide Tencent Cloud credentials")
          /// Audio is sent to Tencent Cloud. The app ID, secret ID, and secret key are stored in local credentials and can be shown or hidden with the eye button.
          internal static let privacyNote = ScreenshotL10n.tr("Localizable", "asr.provider.tencent.privacy_note", fallback: "Audio is sent to Tencent Cloud. The app ID, secret ID, and secret key are stored in local credentials and can be shown or hidden with the eye button.")
          /// Secret ID
          internal static let secretId = ScreenshotL10n.tr("Localizable", "asr.provider.tencent.secret_id", fallback: "Secret ID")
          /// Secret Key
          internal static let secretKey = ScreenshotL10n.tr("Localizable", "asr.provider.tencent.secret_key", fallback: "Secret Key")
          /// Show Tencent Cloud credentials
          internal static let showCredentials = ScreenshotL10n.tr("Localizable", "asr.provider.tencent.show_credentials", fallback: "Show Tencent Cloud credentials")
        }
      }
    }
    internal enum Asset {
      internal enum Action {
        /// ===== Asset =====
        internal static let attachToAiChat = ScreenshotL10n.tr("Localizable", "asset.action.attach_to_ai_chat", fallback: "Attach to AI Chat")
        /// Copy
        internal static let copy = ScreenshotL10n.tr("Localizable", "asset.action.copy", fallback: "Copy")
        /// Copy File
        internal static let copyFile = ScreenshotL10n.tr("Localizable", "asset.action.copy_file", fallback: "Copy File")
        /// Copy File Path
        internal static let copyFilePath = ScreenshotL10n.tr("Localizable", "asset.action.copy_file_path", fallback: "Copy File Path")
        /// Copy Image
        internal static let copyImage = ScreenshotL10n.tr("Localizable", "asset.action.copy_image", fallback: "Copy Image")
        /// Copy OCR Text
        internal static let copyOcrText = ScreenshotL10n.tr("Localizable", "asset.action.copy_ocr_text", fallback: "Copy OCR Text")
        /// Delete
        internal static let delete = ScreenshotL10n.tr("Localizable", "asset.action.delete", fallback: "Delete")
        /// Paste
        internal static let paste = ScreenshotL10n.tr("Localizable", "asset.action.paste", fallback: "Paste")
        /// Paste and Keep Open
        internal static let pasteAndKeepOpen = ScreenshotL10n.tr("Localizable", "asset.action.paste_and_keep_open", fallback: "Paste and Keep Open")
        /// Paste File
        internal static let pasteFile = ScreenshotL10n.tr("Localizable", "asset.action.paste_file", fallback: "Paste File")
        /// Paste File Path
        internal static let pasteFilePath = ScreenshotL10n.tr("Localizable", "asset.action.paste_file_path", fallback: "Paste File Path")
        /// Paste OCR Text
        internal static let pasteOcrText = ScreenshotL10n.tr("Localizable", "asset.action.paste_ocr_text", fallback: "Paste OCR Text")
        /// Pin
        internal static let pin = ScreenshotL10n.tr("Localizable", "asset.action.pin", fallback: "Pin")
        /// Quick Look
        internal static let quickLook = ScreenshotL10n.tr("Localizable", "asset.action.quick_look", fallback: "Quick Look")
        /// Rerun OCR
        internal static let rerunOcr = ScreenshotL10n.tr("Localizable", "asset.action.rerun_ocr", fallback: "Rerun OCR")
        /// Save as File
        internal static let saveAsFile = ScreenshotL10n.tr("Localizable", "asset.action.save_as_file", fallback: "Save as File")
      }
      internal enum MediaFilter {
        /// All
        internal static let all = ScreenshotL10n.tr("Localizable", "asset.media_filter.all", fallback: "All")
        /// Favorites
        internal static let favorites = ScreenshotL10n.tr("Localizable", "asset.media_filter.favorites", fallback: "Favorites")
        /// Recordings
        internal static let recordings = ScreenshotL10n.tr("Localizable", "asset.media_filter.recordings", fallback: "Recordings")
        /// Screenshots
        internal static let screenshots = ScreenshotL10n.tr("Localizable", "asset.media_filter.screenshots", fallback: "Screenshots")
      }
      internal enum ScreenshotFilter {
        /// ===== Asset =====
        internal static let all = ScreenshotL10n.tr("Localizable", "asset.screenshot_filter.all", fallback: "All")
        /// Favorites
        internal static let favorites = ScreenshotL10n.tr("Localizable", "asset.screenshot_filter.favorites", fallback: "Favorites")
        /// This Month
        internal static let thisMonth = ScreenshotL10n.tr("Localizable", "asset.screenshot_filter.this_month", fallback: "This Month")
        /// This Week
        internal static let thisWeek = ScreenshotL10n.tr("Localizable", "asset.screenshot_filter.this_week", fallback: "This Week")
        /// Today
        internal static let today = ScreenshotL10n.tr("Localizable", "asset.screenshot_filter.today", fallback: "Today")
      }
    }
    internal enum Audio {
      internal enum Capture {
        internal enum Error {
          /// ===== Audio =====
          internal static func busy(_ p1: Any, _ p2: Any) -> String {
            return ScreenshotL10n.tr("Localizable", "audio.capture.error.busy", String(describing: p1), String(describing: p2), fallback: "Audio capture is currently busy (active: %@, requested: %@).")
          }
        }
        internal enum Kind {
          /// Task Assistant
          internal static let agentCompose = ScreenshotL10n.tr("Localizable", "audio.capture.kind.agent_compose", fallback: "Task Assistant")
          /// Dictation
          internal static let dictation = ScreenshotL10n.tr("Localizable", "audio.capture.kind.dictation", fallback: "Dictation")
          /// Notes
          internal static let notes = ScreenshotL10n.tr("Localizable", "audio.capture.kind.notes", fallback: "Notes")
        }
      }
      internal enum Recorder {
        internal enum Error {
          /// No available microphone was detected. Please connect or enable an input device and try again.
          internal static let microphoneUnavailable = ScreenshotL10n.tr("Localizable", "audio.recorder.error.microphone_unavailable", fallback: "No available microphone was detected. Please connect or enable an input device and try again.")
        }
      }
    }
    internal enum AudioRecorder {
      internal enum Error {
        /// No microphone access. Please allow VoxFlow to use the microphone in System Settings.
        internal static let microphonePermissionDenied = ScreenshotL10n.tr("Localizable", "audio_recorder.error.microphone_permission_denied", fallback: "No microphone access. Please allow VoxFlow to use the microphone in System Settings.")
      }
    }
    internal enum Chat {
      internal enum Action {
        /// Close
        internal static let close = ScreenshotL10n.tr("Localizable", "chat.action.close", fallback: "Close")
      }
      internal enum Error {
        /// AI model is not configured
        internal static let modelNotConfigured = ScreenshotL10n.tr("Localizable", "chat.error.model_not_configured", fallback: "AI model is not configured")
      }
      internal enum Input {
        /// Ask or paste a question
        internal static let placeholder = ScreenshotL10n.tr("Localizable", "chat.input.placeholder", fallback: "Ask or paste a question")
        /// Send
        internal static let send = ScreenshotL10n.tr("Localizable", "chat.input.send", fallback: "Send")
        /// Stop
        internal static let stop = ScreenshotL10n.tr("Localizable", "chat.input.stop", fallback: "Stop")
      }
      internal enum Message {
        /// Assistant
        internal static let assistantRole = ScreenshotL10n.tr("Localizable", "chat.message.assistant_role", fallback: "Assistant")
        /// Copy reply
        internal static let copyReply = ScreenshotL10n.tr("Localizable", "chat.message.copy_reply", fallback: "Copy reply")
        /// Copy this reply
        internal static let copyReplyHelp = ScreenshotL10n.tr("Localizable", "chat.message.copy_reply_help", fallback: "Copy this reply")
        /// Message failed: %@
        internal static func failedFormat(_ p1: Any) -> String {
          return ScreenshotL10n.tr("Localizable", "chat.message.failed_format", String(describing: p1), fallback: "Message failed: %@")
        }
        /// You
        internal static let userRole = ScreenshotL10n.tr("Localizable", "chat.message.user_role", fallback: "You")
      }
      internal enum Panel {
        /// AI Chat
        internal static let title = ScreenshotL10n.tr("Localizable", "chat.panel.title", fallback: "AI Chat")
      }
      internal enum Status {
        /// Ready
        internal static let ready = ScreenshotL10n.tr("Localizable", "chat.status.ready", fallback: "Ready")
        /// Generating
        internal static let streaming = ScreenshotL10n.tr("Localizable", "chat.status.streaming", fallback: "Generating")
      }
    }
    internal enum Correction {
      /// No aliases yet
      internal static let aliasPreviewEmpty = ScreenshotL10n.tr("Localizable", "correction.alias_preview_empty", fallback: "No aliases yet")
      internal enum Action {
        /// Add alias
        internal static let addAlias = ScreenshotL10n.tr("Localizable", "correction.action.add_alias", fallback: "Add alias")
        /// Add target
        internal static let addTarget = ScreenshotL10n.tr("Localizable", "correction.action.add_target", fallback: "Add target")
        /// Cancel
        internal static let cancel = ScreenshotL10n.tr("Localizable", "correction.action.cancel", fallback: "Cancel")
        /// Clear
        internal static let clear = ScreenshotL10n.tr("Localizable", "correction.action.clear", fallback: "Clear")
        /// Delete alias
        internal static let deleteAlias = ScreenshotL10n.tr("Localizable", "correction.action.delete_alias", fallback: "Delete alias")
        /// Pause alias
        internal static let pauseAlias = ScreenshotL10n.tr("Localizable", "correction.action.pause_alias", fallback: "Pause alias")
        /// Save
        internal static let save = ScreenshotL10n.tr("Localizable", "correction.action.save", fallback: "Save")
        /// Undo
        internal static let undo = ScreenshotL10n.tr("Localizable", "correction.action.undo", fallback: "Undo")
      }
      internal enum Alias {
        /// Alternative spellings that should map to the same target term.
        internal static let subtitle = ScreenshotL10n.tr("Localizable", "correction.alias.subtitle", fallback: "Alternative spellings that should map to the same target term.")
        /// Aliases
        internal static let title = ScreenshotL10n.tr("Localizable", "correction.alias.title", fallback: "Aliases")
      }
      internal enum Detail {
        /// Tune matching scope and policy
        internal static let advancedSettingsHelp = ScreenshotL10n.tr("Localizable", "correction.detail.advanced_settings_help", fallback: "Tune matching scope and policy")
        /// Advanced settings
        internal static let advancedSettingsTitle = ScreenshotL10n.tr("Localizable", "correction.detail.advanced_settings_title", fallback: "Advanced settings")
        /// Aliases
        internal static let aliasSectionTitle = ScreenshotL10n.tr("Localizable", "correction.detail.alias_section_title", fallback: "Aliases")
        /// Select or add a term to edit correction rules.
        internal static let noTargetHint = ScreenshotL10n.tr("Localizable", "correction.detail.no_target_hint", fallback: "Select or add a term to edit correction rules.")
        /// No term selected
        internal static let noTargetTitle = ScreenshotL10n.tr("Localizable", "correction.detail.no_target_title", fallback: "No term selected")
        /// Recent automatic learning suggestions appear here.
        internal static let recentLearningText = ScreenshotL10n.tr("Localizable", "correction.detail.recent_learning_text", fallback: "Recent automatic learning suggestions appear here.")
        /// Recent learning
        internal static let recentLearningTitle = ScreenshotL10n.tr("Localizable", "correction.detail.recent_learning_title", fallback: "Recent learning")
      }
      internal enum Dialog {
        /// Clear all rules?
        internal static let clearAllTitle = ScreenshotL10n.tr("Localizable", "correction.dialog.clear_all_title", fallback: "Clear all rules?")
      }
      internal enum Feedback {
        /// Alias added
        internal static let aliasAdded = ScreenshotL10n.tr("Localizable", "correction.feedback.alias_added", fallback: "Alias added")
        /// This alias already exists.
        internal static let aliasDuplicate = ScreenshotL10n.tr("Localizable", "correction.feedback.alias_duplicate", fallback: "This alias already exists.")
        /// Enter an alias first.
        internal static let aliasRequired = ScreenshotL10n.tr("Localizable", "correction.feedback.alias_required", fallback: "Enter an alias first.")
        /// Automatically learned: %@ → %@
        internal static func autoLearningActiveFormat(_ p1: Any, _ p2: Any) -> String {
          return ScreenshotL10n.tr("Localizable", "correction.feedback.auto_learning_active_format", String(describing: p1), String(describing: p2), fallback: "Automatically learned: %@ → %@")
        }
        /// Queued for learning: %@
        internal static func autoLearningPendingFormat(_ p1: Any) -> String {
          return ScreenshotL10n.tr("Localizable", "correction.feedback.auto_learning_pending_format", String(describing: p1), fallback: "Queued for learning: %@")
        }
        /// Learned automatically: %@
        internal static func autoLearningRecordedFormat(_ p1: Any) -> String {
          return ScreenshotL10n.tr("Localizable", "correction.feedback.auto_learning_recorded_format", String(describing: p1), fallback: "Learned automatically: %@")
        }
        /// Automatically learned %d items. Click to undo.
        internal static func learningBatchFormat(_ p1: Int) -> String {
          return ScreenshotL10n.tr("Localizable", "correction.feedback.learning_batch_format", p1, fallback: "Automatically learned %d items. Click to undo.")
        }
        /// Learning confirmed
        internal static let learningConfirmed = ScreenshotL10n.tr("Localizable", "correction.feedback.learning_confirmed", fallback: "Learning confirmed")
        /// Rule created
        internal static let ruleCreated = ScreenshotL10n.tr("Localizable", "correction.feedback.rule_created", fallback: "Rule created")
        /// Rule deleted
        internal static let ruleDeleted = ScreenshotL10n.tr("Localizable", "correction.feedback.rule_deleted", fallback: "Rule deleted")
        /// Rule paused
        internal static let rulePaused = ScreenshotL10n.tr("Localizable", "correction.feedback.rule_paused", fallback: "Rule paused")
        /// Rule saved
        internal static let ruleSaved = ScreenshotL10n.tr("Localizable", "correction.feedback.rule_saved", fallback: "Rule saved")
        /// Rules cleared
        internal static let rulesCleared = ScreenshotL10n.tr("Localizable", "correction.feedback.rules_cleared", fallback: "Rules cleared")
        /// Target added
        internal static let targetAdded = ScreenshotL10n.tr("Localizable", "correction.feedback.target_added", fallback: "Target added")
        /// Enter a target term first.
        internal static let targetRequired = ScreenshotL10n.tr("Localizable", "correction.feedback.target_required", fallback: "Enter a target term first.")
        /// Learning batch undone.
        internal static let undoBatch = ScreenshotL10n.tr("Localizable", "correction.feedback.undo_batch", fallback: "Learning batch undone.")
        /// Undid the latest change
        internal static let undoLatest = ScreenshotL10n.tr("Localizable", "correction.feedback.undo_latest", fallback: "Undid the latest change")
        /// Nothing to undo
        internal static let undoNone = ScreenshotL10n.tr("Localizable", "correction.feedback.undo_none", fallback: "Nothing to undo")
        /// Nothing to undo.
        internal static let undoNotAvailable = ScreenshotL10n.tr("Localizable", "correction.feedback.undo_not_available", fallback: "Nothing to undo.")
      }
      internal enum Filter {
        /// Active
        internal static let active = ScreenshotL10n.tr("Localizable", "correction.filter.active", fallback: "Active")
        /// All
        internal static let all = ScreenshotL10n.tr("Localizable", "correction.filter.all", fallback: "All")
        /// Candidates
        internal static let candidate = ScreenshotL10n.tr("Localizable", "correction.filter.candidate", fallback: "Candidates")
        /// Suspended
        internal static let suspended = ScreenshotL10n.tr("Localizable", "correction.filter.suspended", fallback: "Suspended")
      }
      internal enum Help {
        /// Add a correction target
        internal static let addTarget = ScreenshotL10n.tr("Localizable", "correction.help.add_target", fallback: "Add a correction target")
        /// Remove all aliases
        internal static let clearAliases = ScreenshotL10n.tr("Localizable", "correction.help.clear_aliases", fallback: "Remove all aliases")
      }
      internal enum Lifecycle {
        /// Active
        internal static let active = ScreenshotL10n.tr("Localizable", "correction.lifecycle.active", fallback: "Active")
        /// Candidate
        internal static let candidate = ScreenshotL10n.tr("Localizable", "correction.lifecycle.candidate", fallback: "Candidate")
        /// Retired
        internal static let retired = ScreenshotL10n.tr("Localizable", "correction.lifecycle.retired", fallback: "Retired")
        /// Paused
        internal static let suspended = ScreenshotL10n.tr("Localizable", "correction.lifecycle.suspended", fallback: "Paused")
      }
      internal enum List {
        /// Add hotwords or text replacements to build your vocabulary.
        internal static let emptyHint = ScreenshotL10n.tr("Localizable", "correction.list.empty_hint", fallback: "Add hotwords or text replacements to build your vocabulary.")
        /// No vocabulary rules yet
        internal static let emptyTitle = ScreenshotL10n.tr("Localizable", "correction.list.empty_title", fallback: "No vocabulary rules yet")
      }
      internal enum MatchPolicy {
        /// Word boundary
        internal static let boundary = ScreenshotL10n.tr("Localizable", "correction.match_policy.boundary", fallback: "Word boundary")
        /// Exact match
        internal static let exact = ScreenshotL10n.tr("Localizable", "correction.match_policy.exact", fallback: "Exact match")
        /// Contains text
        internal static let substring = ScreenshotL10n.tr("Localizable", "correction.match_policy.substring", fallback: "Contains text")
      }
      internal enum Popover {
        /// Add a spelling variant for this term
        internal static let addAliasHint = ScreenshotL10n.tr("Localizable", "correction.popover.add_alias_hint", fallback: "Add a spelling variant for this term")
        /// Add alias
        internal static let addAliasTitle = ScreenshotL10n.tr("Localizable", "correction.popover.add_alias_title", fallback: "Add alias")
        /// Aliases
        internal static let aliasesTitle = ScreenshotL10n.tr("Localizable", "correction.popover.aliases_title", fallback: "Aliases")
        /// New target term
        internal static let newTargetTitle = ScreenshotL10n.tr("Localizable", "correction.popover.new_target_title", fallback: "New target term")
      }
      internal enum Scope {
        /// Current app
        internal static let currentApplication = ScreenshotL10n.tr("Localizable", "correction.scope.current_application", fallback: "Current app")
        /// All apps
        internal static let global = ScreenshotL10n.tr("Localizable", "correction.scope.global", fallback: "All apps")
      }
      internal enum Section {
        /// Terms that VoxFlow should recognize and correct consistently.
        internal static let targetLibraryDescription = ScreenshotL10n.tr("Localizable", "correction.section.target_library_description", fallback: "Terms that VoxFlow should recognize and correct consistently.")
        /// Search vocabulary
        internal static let targetLibrarySearchPlaceholder = ScreenshotL10n.tr("Localizable", "correction.section.target_library_search_placeholder", fallback: "Search vocabulary")
        /// Vocabulary library
        internal static let targetLibraryTitle = ScreenshotL10n.tr("Localizable", "correction.section.target_library_title", fallback: "Vocabulary library")
      }
      internal enum Source {
        /// Auto-learned
        internal static let automaticLearning = ScreenshotL10n.tr("Localizable", "correction.source.automatic_learning", fallback: "Auto-learned")
        /// Imported
        internal static let imported = ScreenshotL10n.tr("Localizable", "correction.source.imported", fallback: "Imported")
        /// Manual
        internal static let manual = ScreenshotL10n.tr("Localizable", "correction.source.manual", fallback: "Manual")
      }
      internal enum Table {
        internal enum Header {
          /// Action
          internal static let action = ScreenshotL10n.tr("Localizable", "correction.table.header.action", fallback: "Action")
          /// Count
          internal static let count = ScreenshotL10n.tr("Localizable", "correction.table.header.count", fallback: "Count")
          /// Recent
          internal static let recent = ScreenshotL10n.tr("Localizable", "correction.table.header.recent", fallback: "Recent")
          /// Scope
          internal static let scope = ScreenshotL10n.tr("Localizable", "correction.table.header.scope", fallback: "Scope")
          /// Status
          internal static let status = ScreenshotL10n.tr("Localizable", "correction.table.header.status", fallback: "Status")
          /// Target
          internal static let target = ScreenshotL10n.tr("Localizable", "correction.table.header.target", fallback: "Target")
        }
      }
      internal enum Target {
        /// %d corrections
        internal static func correctionCountFormat(_ p1: Int) -> String {
          return ScreenshotL10n.tr("Localizable", "correction.target.correction_count_format", p1, fallback: "%d corrections")
        }
        /// The preferred spelling or phrase.
        internal static let subtitle = ScreenshotL10n.tr("Localizable", "correction.target.subtitle", fallback: "The preferred spelling or phrase.")
        /// Target term
        internal static let title = ScreenshotL10n.tr("Localizable", "correction.target.title", fallback: "Target term")
      }
      internal enum Time {
        /// %d hours ago
        internal static func hoursAgoFormat(_ p1: Int) -> String {
          return ScreenshotL10n.tr("Localizable", "correction.time.hours_ago_format", p1, fallback: "%d hours ago")
        }
        /// Just now
        internal static let justNow = ScreenshotL10n.tr("Localizable", "correction.time.just_now", fallback: "Just now")
        /// %d minutes ago
        internal static func minutesAgoFormat(_ p1: Int) -> String {
          return ScreenshotL10n.tr("Localizable", "correction.time.minutes_ago_format", p1, fallback: "%d minutes ago")
        }
        /// Never
        internal static let never = ScreenshotL10n.tr("Localizable", "correction.time.never", fallback: "Never")
        /// Yesterday
        internal static let yesterday = ScreenshotL10n.tr("Localizable", "correction.time.yesterday", fallback: "Yesterday")
      }
      internal enum View {
        /// Remove all vocabulary rules and aliases?
        internal static let clearAllMessage = ScreenshotL10n.tr("Localizable", "correction.view.clear_all_message", fallback: "Remove all vocabulary rules and aliases?")
        /// Manage hotwords and text replacement rules for ASR hotword boosting and LLM correction context.
        internal static let description = ScreenshotL10n.tr("Localizable", "correction.view.description", fallback: "Manage hotwords and text replacement rules for ASR hotword boosting and LLM correction context.")
        /// Vocabulary
        internal static let title = ScreenshotL10n.tr("Localizable", "correction.view.title", fallback: "Vocabulary")
      }
      internal enum Weekly {
        /// Vocabulary activity from the last seven days.
        internal static let subtitle = ScreenshotL10n.tr("Localizable", "correction.weekly.subtitle", fallback: "Vocabulary activity from the last seven days.")
        /// This week
        internal static let title = ScreenshotL10n.tr("Localizable", "correction.weekly.title", fallback: "This week")
      }
    }
    internal enum Db {
      internal enum VoiceTask {
        /// ===== Database =====
        internal static let defaultTitle = ScreenshotL10n.tr("Localizable", "db.voice_task.default_title", fallback: "Dictation")
      }
    }
    internal enum Dictation {
      internal enum Asset {
        /// Dictation note
        internal static let defaultTitle = ScreenshotL10n.tr("Localizable", "dictation.asset.default_title", fallback: "Dictation note")
      }
      internal enum Coordinator {
        /// This mode cannot perform this dictation operation.
        internal static let invalidMode = ScreenshotL10n.tr("Localizable", "dictation.coordinator.invalid_mode", fallback: "This mode cannot perform this dictation operation.")
        /// LLM request failed: %@
        internal static func llmCallFailedFormat(_ p1: Any) -> String {
          return ScreenshotL10n.tr("Localizable", "dictation.coordinator.llm_call_failed_format", String(describing: p1), fallback: "LLM request failed: %@")
        }
        /// LLM is not configured. Please configure a model in Settings.
        internal static let llmNotConfigured = ScreenshotL10n.tr("Localizable", "dictation.coordinator.llm_not_configured", fallback: "LLM is not configured. Please configure a model in Settings.")
        /// ===== Dictation =====
        internal static let noActiveTask = ScreenshotL10n.tr("Localizable", "dictation.coordinator.no_active_task", fallback: "No active dictation task to operate on.")
        /// %@ workflow is already running.
        internal static func workflowAlreadyRunningFormat(_ p1: Any) -> String {
          return ScreenshotL10n.tr("Localizable", "dictation.coordinator.workflow_already_running_format", String(describing: p1), fallback: "%@ workflow is already running.")
        }
      }
      internal enum Error {
        /// ===== Dictation and notes =====
        internal static let agentComposeUnavailable = ScreenshotL10n.tr("Localizable", "dictation.error.agent_compose_unavailable", fallback: "Task assistant is not ready yet. Restart VoxFlow and try again.")
        /// AI coding console is not ready yet. Restart VoxFlow and try again.
        internal static let agentDispatchUnavailable = ScreenshotL10n.tr("Localizable", "dictation.error.agent_dispatch_unavailable", fallback: "AI coding console is not ready yet. Restart VoxFlow and try again.")
        /// Dictation is already running.
        internal static let alreadyRunning = ScreenshotL10n.tr("Localizable", "dictation.error.already_running", fallback: "Dictation is already running.")
        /// Timed out while waiting for the final transcription result.
        internal static let finalResultTimedOut = ScreenshotL10n.tr("Localizable", "dictation.error.final_result_timed_out", fallback: "Timed out while waiting for the final transcription result.")
        /// Unsupported dictation language: %@.
        internal static func unsupportedLanguageFormat(_ p1: Any) -> String {
          return ScreenshotL10n.tr("Localizable", "dictation.error.unsupported_language_format", String(describing: p1), fallback: "Unsupported dictation language: %@.")
        }
      }
      internal enum Hud {
        /// Composing response from context...
        internal static let contextFusion = ScreenshotL10n.tr("Localizable", "dictation.hud.context_fusion", fallback: "Composing response from context...")
      }
    }
    internal enum Help {
      internal enum Actions {
        /// Check whether a newer VoxFlow release is available.
        internal static let checkUpdatesSubtitle = ScreenshotL10n.tr("Localizable", "help.actions.check_updates_subtitle", fallback: "Check whether a newer VoxFlow release is available.")
        /// Check for Updates
        internal static let checkUpdatesTitle = ScreenshotL10n.tr("Localizable", "help.actions.check_updates_title", fallback: "Check for Updates")
        /// Open support and community links.
        internal static let communitySubtitle = ScreenshotL10n.tr("Localizable", "help.actions.community_subtitle", fallback: "Open support and community links.")
        /// Community support
        internal static let communityTitle = ScreenshotL10n.tr("Localizable", "help.actions.community_title", fallback: "Community support")
      }
      internal enum Cards {
        /// Send dictated tasks to local coding-agent terminals.
        internal static let aiCodingSubtitle = ScreenshotL10n.tr("Localizable", "help.cards.ai_coding_subtitle", fallback: "Send dictated tasks to local coding-agent terminals.")
        /// AI Coding
        internal static let aiCodingTitle = ScreenshotL10n.tr("Localizable", "help.cards.ai_coding_title", fallback: "AI Coding")
        /// Search assets, commands, and app workflows from one palette.
        internal static let commandPanelSubtitle = ScreenshotL10n.tr("Localizable", "help.cards.command_panel_subtitle", fallback: "Search assets, commands, and app workflows from one palette.")
        /// Command palette
        internal static let commandPanelTitle = ScreenshotL10n.tr("Localizable", "help.cards.command_panel_title", fallback: "Command palette")
        /// Manage hotwords and text replacements for more reliable recognition.
        internal static let easyCorrectionSubtitle = ScreenshotL10n.tr("Localizable", "help.cards.easy_correction_subtitle", fallback: "Manage hotwords and text replacements for more reliable recognition.")
        /// Vocabulary correction
        internal static let easyCorrectionTitle = ScreenshotL10n.tr("Localizable", "help.cards.easy_correction_title", fallback: "Vocabulary correction")
        /// Audio, screenshots, recordings, and history stay local unless you choose a cloud provider.
        internal static let localPrivacySubtitle = ScreenshotL10n.tr("Localizable", "help.cards.local_privacy_subtitle", fallback: "Audio, screenshots, recordings, and history stay local unless you choose a cloud provider.")
        /// Local-first privacy
        internal static let localPrivacyTitle = ScreenshotL10n.tr("Localizable", "help.cards.local_privacy_title", fallback: "Local-first privacy")
        /// When recognition or correction fails, VoxFlow keeps your original text and avoids destructive changes.
        internal static let safeFallbackSubtitle = ScreenshotL10n.tr("Localizable", "help.cards.safe_fallback_subtitle", fallback: "When recognition or correction fails, VoxFlow keeps your original text and avoids destructive changes.")
        /// Safe fallback
        internal static let safeFallbackTitle = ScreenshotL10n.tr("Localizable", "help.cards.safe_fallback_title", fallback: "Safe fallback")
        /// Capture screenshots, extract text, translate, summarize, and reuse them.
        internal static let screenshotOcrSubtitle = ScreenshotL10n.tr("Localizable", "help.cards.screenshot_ocr_subtitle", fallback: "Capture screenshots, extract text, translate, summarize, and reuse them.")
        /// Screenshot OCR
        internal static let screenshotOcrTitle = ScreenshotL10n.tr("Localizable", "help.cards.screenshot_ocr_title", fallback: "Screenshot OCR")
        /// Use notes to keep dictated text, screenshots, and recordings available for review.
        internal static let transcriptionNotesSubtitle = ScreenshotL10n.tr("Localizable", "help.cards.transcription_notes_subtitle", fallback: "Use notes to keep dictated text, screenshots, and recordings available for review.")
        /// Transcription notes
        internal static let transcriptionNotesTitle = ScreenshotL10n.tr("Localizable", "help.cards.transcription_notes_title", fallback: "Transcription notes")
      }
      internal enum Links {
        /// Report a bug or request a feature on GitHub.
        internal static let feedbackSubtitle = ScreenshotL10n.tr("Localizable", "help.links.feedback_subtitle", fallback: "Report a bug or request a feature on GitHub.")
        /// Feedback
        internal static let feedbackTitle = ScreenshotL10n.tr("Localizable", "help.links.feedback_title", fallback: "Feedback")
        /// View source code and project activity.
        internal static let githubSubtitle = ScreenshotL10n.tr("Localizable", "help.links.github_subtitle", fallback: "View source code and project activity.")
        /// GitHub repository
        internal static let githubTitle = ScreenshotL10n.tr("Localizable", "help.links.github_title", fallback: "GitHub repository")
        /// Read what VoxFlow stores locally and what may be sent to providers.
        internal static let privacySubtitle = ScreenshotL10n.tr("Localizable", "help.links.privacy_subtitle", fallback: "Read what VoxFlow stores locally and what may be sent to providers.")
        /// Privacy policy
        internal static let privacyTitle = ScreenshotL10n.tr("Localizable", "help.links.privacy_title", fallback: "Privacy policy")
        /// Open the VoxFlow project homepage in your browser.
        internal static let projectHomepageSubtitle = ScreenshotL10n.tr("Localizable", "help.links.project_homepage_subtitle", fallback: "Open the VoxFlow project homepage in your browser.")
        /// Project homepage
        internal static let projectHomepageTitle = ScreenshotL10n.tr("Localizable", "help.links.project_homepage_title", fallback: "Project homepage")
        /// See what changed in recent versions.
        internal static let releaseSubtitle = ScreenshotL10n.tr("Localizable", "help.links.release_subtitle", fallback: "See what changed in recent versions.")
        /// Release notes
        internal static let releaseTitle = ScreenshotL10n.tr("Localizable", "help.links.release_title", fallback: "Release notes")
      }
      internal enum Overlay {
        /// Star the project on GitHub or join the community.
        internal static let githubStarSubtitle = ScreenshotL10n.tr("Localizable", "help.overlay.github_star_subtitle", fallback: "Star the project on GitHub or join the community.")
        /// Support VoxFlow
        internal static let githubStarTitle = ScreenshotL10n.tr("Localizable", "help.overlay.github_star_title", fallback: "Support VoxFlow")
        /// Find community and project links.
        internal static let subtitle = ScreenshotL10n.tr("Localizable", "help.overlay.subtitle", fallback: "Find community and project links.")
        /// Community
        internal static let title = ScreenshotL10n.tr("Localizable", "help.overlay.title", fallback: "Community")
      }
      internal enum Page {
        /// Tips, shortcuts, permissions, and project links.
        internal static let subtitle = ScreenshotL10n.tr("Localizable", "help.page.subtitle", fallback: "Tips, shortcuts, permissions, and project links.")
        /// Help
        internal static let title = ScreenshotL10n.tr("Localizable", "help.page.title", fallback: "Help")
      }
      internal enum Permissions {
        /// Required for global shortcuts and text insertion.
        internal static let accessibilitySubtitle = ScreenshotL10n.tr("Localizable", "help.permissions.accessibility_subtitle", fallback: "Required for global shortcuts and text insertion.")
        /// Accessibility
        internal static let accessibilityTitle = ScreenshotL10n.tr("Localizable", "help.permissions.accessibility_title", fallback: "Accessibility")
        /// Required for dictation and recording audio.
        internal static let microphoneSubtitle = ScreenshotL10n.tr("Localizable", "help.permissions.microphone_subtitle", fallback: "Required for dictation and recording audio.")
        /// Microphone
        internal static let microphoneTitle = ScreenshotL10n.tr("Localizable", "help.permissions.microphone_title", fallback: "Microphone")
        /// Open Settings
        internal static let openSettings = ScreenshotL10n.tr("Localizable", "help.permissions.open_settings", fallback: "Open Settings")
        /// Required for screenshot OCR and screen recording.
        internal static let screenRecordingSubtitle = ScreenshotL10n.tr("Localizable", "help.permissions.screen_recording_subtitle", fallback: "Required for screenshot OCR and screen recording.")
        /// Screen Recording
        internal static let screenRecordingTitle = ScreenshotL10n.tr("Localizable", "help.permissions.screen_recording_title", fallback: "Screen Recording")
        /// Required when using Apple Speech features.
        internal static let speechSubtitle = ScreenshotL10n.tr("Localizable", "help.permissions.speech_subtitle", fallback: "Required when using Apple Speech features.")
        /// Speech Recognition
        internal static let speechTitle = ScreenshotL10n.tr("Localizable", "help.permissions.speech_title", fallback: "Speech Recognition")
      }
      internal enum QrUnavailable {
        /// The community QR code could not be loaded.
        internal static let description = ScreenshotL10n.tr("Localizable", "help.qr_unavailable.description", fallback: "The community QR code could not be loaded.")
        /// QR code unavailable
        internal static let title = ScreenshotL10n.tr("Localizable", "help.qr_unavailable.title", fallback: "QR code unavailable")
      }
      internal enum Section {
        /// Check the macOS permissions VoxFlow needs.
        internal static let permissionsSubtitle = ScreenshotL10n.tr("Localizable", "help.section.permissions_subtitle", fallback: "Check the macOS permissions VoxFlow needs.")
        /// Permissions
        internal static let permissionsTitle = ScreenshotL10n.tr("Localizable", "help.section.permissions_title", fallback: "Permissions")
        /// Project, release, feedback, and privacy links.
        internal static let quickLinksSubtitle = ScreenshotL10n.tr("Localizable", "help.section.quick_links_subtitle", fallback: "Project, release, feedback, and privacy links.")
        /// Quick links
        internal static let quickLinksTitle = ScreenshotL10n.tr("Localizable", "help.section.quick_links_title", fallback: "Quick links")
      }
      internal enum Shortcuts {
        /// Shortcut or middle mouse button
        internal static let displayNameWithMiddleMouse = ScreenshotL10n.tr("Localizable", "help.shortcuts.display_name_with_middle_mouse", fallback: "Shortcut or middle mouse button")
        /// Hold the shortcut to dictate, release to finish.
        internal static let subtitleHold = ScreenshotL10n.tr("Localizable", "help.shortcuts.subtitle_hold", fallback: "Hold the shortcut to dictate, release to finish.")
        /// Hold the shortcut or press the middle mouse button to dictate.
        internal static let subtitleHoldWithMiddleMouse = ScreenshotL10n.tr("Localizable", "help.shortcuts.subtitle_hold_with_middle_mouse", fallback: "Hold the shortcut or press the middle mouse button to dictate.")
        /// Press the shortcut to start, press again to stop.
        internal static let subtitleToggle = ScreenshotL10n.tr("Localizable", "help.shortcuts.subtitle_toggle", fallback: "Press the shortcut to start, press again to stop.")
        /// Press the shortcut or middle mouse button to start or stop dictation.
        internal static let subtitleToggleWithMiddleMouse = ScreenshotL10n.tr("Localizable", "help.shortcuts.subtitle_toggle_with_middle_mouse", fallback: "Press the shortcut or middle mouse button to start or stop dictation.")
      }
    }
    internal enum Home {
      internal enum Activity {
        /// Clear
        internal static let clear = ScreenshotL10n.tr("Localizable", "home.activity.clear", fallback: "Clear")
        /// %@ · %d assets
        internal static func dayAssetsFormat(_ p1: Any, _ p2: Int) -> String {
          return ScreenshotL10n.tr("Localizable", "home.activity.day_assets_format", String(describing: p1), p2, fallback: "%@ · %d assets")
        }
        /// Less
        internal static let less = ScreenshotL10n.tr("Localizable", "home.activity.less", fallback: "Less")
        /// More
        internal static let more = ScreenshotL10n.tr("Localizable", "home.activity.more", fallback: "More")
        /// Past 52 weeks · each square is one day
        internal static let subtitle = ScreenshotL10n.tr("Localizable", "home.activity.subtitle", fallback: "Past 52 weeks · each square is one day")
        /// %d assets this week
        internal static func thisWeekAssetsFormat(_ p1: Int) -> String {
          return ScreenshotL10n.tr("Localizable", "home.activity.this_week_assets_format", p1, fallback: "%d assets this week")
        }
        /// Input Activity
        internal static let title = ScreenshotL10n.tr("Localizable", "home.activity.title", fallback: "Input Activity")
        /// %@ · 0 assets
        internal static func tooltipEmptyFormat(_ p1: Any) -> String {
          return ScreenshotL10n.tr("Localizable", "home.activity.tooltip_empty_format", String(describing: p1), fallback: "%@ · 0 assets")
        }
        internal enum Weekday {
          /// F
          internal static let friday = ScreenshotL10n.tr("Localizable", "home.activity.weekday.friday", fallback: "F")
          /// M
          internal static let monday = ScreenshotL10n.tr("Localizable", "home.activity.weekday.monday", fallback: "M")
          /// S
          internal static let saturday = ScreenshotL10n.tr("Localizable", "home.activity.weekday.saturday", fallback: "S")
          /// S
          internal static let sunday = ScreenshotL10n.tr("Localizable", "home.activity.weekday.sunday", fallback: "S")
          /// T
          internal static let thursday = ScreenshotL10n.tr("Localizable", "home.activity.weekday.thursday", fallback: "T")
          /// T
          internal static let tuesday = ScreenshotL10n.tr("Localizable", "home.activity.weekday.tuesday", fallback: "T")
          /// W
          internal static let wednesday = ScreenshotL10n.tr("Localizable", "home.activity.weekday.wednesday", fallback: "W")
        }
      }
      internal enum Assets {
        /// Clear Data
        internal static let clearAll = ScreenshotL10n.tr("Localizable", "home.assets.clear_all", fallback: "Clear Data")
        /// Copy
        internal static let copy = ScreenshotL10n.tr("Localizable", "home.assets.copy", fallback: "Copy")
        /// %d items
        internal static func countFormat(_ p1: Int) -> String {
          return ScreenshotL10n.tr("Localizable", "home.assets.count_format", p1, fallback: "%d items")
        }
        /// Delete
        internal static let delete = ScreenshotL10n.tr("Localizable", "home.assets.delete", fallback: "Delete")
        /// Delete Selected
        internal static let deleteSelected = ScreenshotL10n.tr("Localizable", "home.assets.delete_selected", fallback: "Delete Selected")
        /// Deselect All
        internal static let deselectAll = ScreenshotL10n.tr("Localizable", "home.assets.deselect_all", fallback: "Deselect All")
        /// No assets
        internal static let empty = ScreenshotL10n.tr("Localizable", "home.assets.empty", fallback: "No assets")
        /// Next
        internal static let nextPage = ScreenshotL10n.tr("Localizable", "home.assets.next_page", fallback: "Next")
        /// No preview available
        internal static let noPreview = ScreenshotL10n.tr("Localizable", "home.assets.no_preview", fallback: "No preview available")
        /// Per page
        internal static let pageSize = ScreenshotL10n.tr("Localizable", "home.assets.page_size", fallback: "Per page")
        /// %d/page
        internal static func pageSizeOptionFormat(_ p1: Int) -> String {
          return ScreenshotL10n.tr("Localizable", "home.assets.page_size_option_format", p1, fallback: "%d/page")
        }
        /// Previous
        internal static let previousPage = ScreenshotL10n.tr("Localizable", "home.assets.previous_page", fallback: "Previous")
        /// Search assets
        internal static let searchPlaceholder = ScreenshotL10n.tr("Localizable", "home.assets.search_placeholder", fallback: "Search assets")
        /// Select All
        internal static let selectAll = ScreenshotL10n.tr("Localizable", "home.assets.select_all", fallback: "Select All")
        /// Assets
        internal static let title = ScreenshotL10n.tr("Localizable", "home.assets.title", fallback: "Assets")
      }
      internal enum ContentType {
        /// Color
        internal static let color = ScreenshotL10n.tr("Localizable", "home.content_type.color", fallback: "Color")
        /// File
        internal static let file = ScreenshotL10n.tr("Localizable", "home.content_type.file", fallback: "File")
        /// Image
        internal static let image = ScreenshotL10n.tr("Localizable", "home.content_type.image", fallback: "Image")
        /// Link
        internal static let link = ScreenshotL10n.tr("Localizable", "home.content_type.link", fallback: "Link")
        /// Text
        internal static let text = ScreenshotL10n.tr("Localizable", "home.content_type.text", fallback: "Text")
      }
      internal enum Date {
        /// Today
        internal static let today = ScreenshotL10n.tr("Localizable", "home.date.today", fallback: "Today")
        /// Yesterday
        internal static let yesterday = ScreenshotL10n.tr("Localizable", "home.date.yesterday", fallback: "Yesterday")
      }
      internal enum Detail {
        /// %.1f seconds
        internal static func durationSecondsFormat(_ p1: Float) -> String {
          return ScreenshotL10n.tr("Localizable", "home.detail.duration_seconds_format", p1, fallback: "%.1f seconds")
        }
        /// %d items
        internal static func itemsFormat(_ p1: Int) -> String {
          return ScreenshotL10n.tr("Localizable", "home.detail.items_format", p1, fallback: "%d items")
        }
        /// Reason: %@
        internal static func reasonFormat(_ p1: Any) -> String {
          return ScreenshotL10n.tr("Localizable", "home.detail.reason_format", String(describing: p1), fallback: "Reason: %@")
        }
        /// %d replacements
        internal static func replacementsFormat(_ p1: Int) -> String {
          return ScreenshotL10n.tr("Localizable", "home.detail.replacements_format", p1, fallback: "%d replacements")
        }
        /// %d seconds
        internal static func secondsFormat(_ p1: Int) -> String {
          return ScreenshotL10n.tr("Localizable", "home.detail.seconds_format", p1, fallback: "%d seconds")
        }
        /// Warning: %@
        internal static func warningFormat(_ p1: Any) -> String {
          return ScreenshotL10n.tr("Localizable", "home.detail.warning_format", String(describing: p1), fallback: "Warning: %@")
        }
        internal enum Action {
          /// Home detail
          internal static let cancel = ScreenshotL10n.tr("Localizable", "home.detail.action.cancel", fallback: "Cancel")
          /// Copy
          internal static let copy = ScreenshotL10n.tr("Localizable", "home.detail.action.copy", fallback: "Copy")
          /// Copy Diagnostic
          internal static let copyDiagnostic = ScreenshotL10n.tr("Localizable", "home.detail.action.copy_diagnostic", fallback: "Copy Diagnostic")
          /// Copy Result
          internal static let copyResult = ScreenshotL10n.tr("Localizable", "home.detail.action.copy_result", fallback: "Copy Result")
          /// Edit
          internal static let edit = ScreenshotL10n.tr("Localizable", "home.detail.action.edit", fallback: "Edit")
          /// Processing
          internal static let processing = ScreenshotL10n.tr("Localizable", "home.detail.action.processing", fallback: "Processing")
          /// Reprocess
          internal static let reprocess = ScreenshotL10n.tr("Localizable", "home.detail.action.reprocess", fallback: "Reprocess")
          /// Save
          internal static let save = ScreenshotL10n.tr("Localizable", "home.detail.action.save", fallback: "Save")
        }
        internal enum Asr {
          /// Alibaba Cloud ASR
          internal static let aliyun = ScreenshotL10n.tr("Localizable", "home.detail.asr.aliyun", fallback: "Alibaba Cloud ASR")
          /// Apple Speech
          internal static let appleSpeech = ScreenshotL10n.tr("Localizable", "home.detail.asr.apple_speech", fallback: "Apple Speech")
          /// AssemblyAI ASR
          internal static let assemblyai = ScreenshotL10n.tr("Localizable", "home.detail.asr.assemblyai", fallback: "AssemblyAI ASR")
          /// ElevenLabs Scribe ASR
          internal static let elevenlabs = ScreenshotL10n.tr("Localizable", "home.detail.asr.elevenlabs", fallback: "ElevenLabs Scribe ASR")
          /// FunASR Local
          internal static let funasr = ScreenshotL10n.tr("Localizable", "home.detail.asr.funasr", fallback: "FunASR Local")
          /// Groq Cloud
          internal static let groq = ScreenshotL10n.tr("Localizable", "home.detail.asr.groq", fallback: "Groq Cloud")
          /// Mistral Voxtral ASR
          internal static let mistralVoxtral = ScreenshotL10n.tr("Localizable", "home.detail.asr.mistral_voxtral", fallback: "Mistral Voxtral ASR")
          /// NVIDIA Nemotron Local
          internal static let nvidiaNemotron = ScreenshotL10n.tr("Localizable", "home.detail.asr.nvidia_nemotron", fallback: "NVIDIA Nemotron Local")
          /// Omnilingual Local
          internal static let omnilingual = ScreenshotL10n.tr("Localizable", "home.detail.asr.omnilingual", fallback: "Omnilingual Local")
          /// Paraformer Local
          internal static let paraformer = ScreenshotL10n.tr("Localizable", "home.detail.asr.paraformer", fallback: "Paraformer Local")
          /// Parakeet Local
          internal static let parakeet = ScreenshotL10n.tr("Localizable", "home.detail.asr.parakeet", fallback: "Parakeet Local")
          /// Qwen3 Local
          internal static let qwen3 = ScreenshotL10n.tr("Localizable", "home.detail.asr.qwen3", fallback: "Qwen3 Local")
          /// SenseVoice Local
          internal static let senseVoice = ScreenshotL10n.tr("Localizable", "home.detail.asr.sense_voice", fallback: "SenseVoice Local")
          /// Tencent Cloud ASR
          internal static let tencent = ScreenshotL10n.tr("Localizable", "home.detail.asr.tencent", fallback: "Tencent Cloud ASR")
          /// Volcengine ASR
          internal static let volcengine = ScreenshotL10n.tr("Localizable", "home.detail.asr.volcengine", fallback: "Volcengine ASR")
          /// Whisper Local
          internal static let whisper = ScreenshotL10n.tr("Localizable", "home.detail.asr.whisper", fallback: "Whisper Local")
        }
        internal enum Context {
          /// Added to Prompt
          internal static let applied = ScreenshotL10n.tr("Localizable", "home.detail.context.applied", fallback: "Added to Prompt")
          /// Candidate Count
          internal static let candidateCount = ScreenshotL10n.tr("Localizable", "home.detail.context.candidate_count", fallback: "Candidate Count")
          /// Candidate Evidence
          internal static let candidateEvidence = ScreenshotL10n.tr("Localizable", "home.detail.context.candidate_evidence", fallback: "Candidate Evidence")
          /// No usable keywords were recognized in the current window.
          internal static let failureNoOcrContext = ScreenshotL10n.tr("Localizable", "home.detail.context.failure_no_ocr_context", fallback: "No usable keywords were recognized in the current window.")
          /// Image OCR context collection timed out; correction continued.
          internal static let failureTimeout = ScreenshotL10n.tr("Localizable", "home.detail.context.failure_timeout", fallback: "Image OCR context collection timed out; correction continued.")
          /// No usable hotwords extracted
          internal static let noHotwords = ScreenshotL10n.tr("Localizable", "home.detail.context.no_hotwords", fallback: "No usable hotwords extracted")
          /// Not Applied
          internal static let notApplied = ScreenshotL10n.tr("Localizable", "home.detail.context.not_applied", fallback: "Not Applied")
          /// OCR Characters
          internal static let ocrCharacters = ScreenshotL10n.tr("Localizable", "home.detail.context.ocr_characters", fallback: "OCR Characters")
          /// Context Source
          internal static let source = ScreenshotL10n.tr("Localizable", "home.detail.context.source", fallback: "Context Source")
          /// Source App
          internal static let sourceApp = ScreenshotL10n.tr("Localizable", "home.detail.context.source_app", fallback: "Source App")
          /// Current Window OCR Text
          internal static let sourceCurrentWindowOcr = ScreenshotL10n.tr("Localizable", "home.detail.context.source_current_window_ocr", fallback: "Current Window OCR Text")
          /// Screenshot OCR Text
          internal static let sourceScreenshotOcr = ScreenshotL10n.tr("Localizable", "home.detail.context.source_screenshot_ocr", fallback: "Screenshot OCR Text")
          /// Image OCR Context
          internal static let title = ScreenshotL10n.tr("Localizable", "home.detail.context.title", fallback: "Image OCR Context")
          /// Top K Candidates
          internal static let topCandidates = ScreenshotL10n.tr("Localizable", "home.detail.context.top_candidates", fallback: "Top K Candidates")
          /// TTL
          internal static let ttl = ScreenshotL10n.tr("Localizable", "home.detail.context.ttl", fallback: "TTL")
          /// Unknown app
          internal static let unknownApp = ScreenshotL10n.tr("Localizable", "home.detail.context.unknown_app", fallback: "Unknown app")
        }
        internal enum Correction {
          /// Disabled
          internal static let disabled = ScreenshotL10n.tr("Localizable", "home.detail.correction.disabled", fallback: "Disabled")
          /// Smart model correction service
          internal static let legacyOpenai = ScreenshotL10n.tr("Localizable", "home.detail.correction.legacy_openai", fallback: "Smart model correction service")
        }
        internal enum Diagnostic {
          /// No warnings
          internal static let noWarnings = ScreenshotL10n.tr("Localizable", "home.detail.diagnostic.no_warnings", fallback: "No warnings")
          /// Full trace recorded
          internal static let recorded = ScreenshotL10n.tr("Localizable", "home.detail.diagnostic.recorded", fallback: "Full trace recorded")
          /// Request
          internal static let request = ScreenshotL10n.tr("Localizable", "home.detail.diagnostic.request", fallback: "Request")
          /// Response
          internal static let response = ScreenshotL10n.tr("Localizable", "home.detail.diagnostic.response", fallback: "Response")
          /// Task Metadata
          internal static let taskMetadata = ScreenshotL10n.tr("Localizable", "home.detail.diagnostic.task_metadata", fallback: "Task Metadata")
          /// Warnings & Errors
          internal static let warnings = ScreenshotL10n.tr("Localizable", "home.detail.diagnostic.warnings", fallback: "Warnings & Errors")
        }
        internal enum Dispatch {
          /// No dispatch result recorded
          internal static let empty = ScreenshotL10n.tr("Localizable", "home.detail.dispatch.empty", fallback: "No dispatch result recorded")
          /// Dispatch Result
          internal static let title = ScreenshotL10n.tr("Localizable", "home.detail.dispatch.title", fallback: "Dispatch Result")
        }
        internal enum Language {
          /// English (US)
          internal static let enUs = ScreenshotL10n.tr("Localizable", "home.detail.language.en_us", fallback: "English (US)")
          /// Chinese (Simplified)
          internal static let zhCn = ScreenshotL10n.tr("Localizable", "home.detail.language.zh_cn", fallback: "Chinese (Simplified)")
          /// Chinese (Traditional)
          internal static let zhTw = ScreenshotL10n.tr("Localizable", "home.detail.language.zh_tw", fallback: "Chinese (Traditional)")
        }
        internal enum Learning {
          /// Saved and learned text replacement from this edit: %@ → %@
          internal static func savedFormat(_ p1: Any, _ p2: Any) -> String {
            return ScreenshotL10n.tr("Localizable", "home.detail.learning.saved_format", String(describing: p1), String(describing: p2), fallback: "Saved and learned text replacement from this edit: %@ → %@")
          }
        }
        internal enum Llm {
          /// Collapse JSON
          internal static let collapseJson = ScreenshotL10n.tr("Localizable", "home.detail.llm.collapse_json", fallback: "Collapse JSON")
          /// corrections
          internal static let corrections = ScreenshotL10n.tr("Localizable", "home.detail.llm.corrections", fallback: "corrections")
          /// Expand full request JSON
          internal static let expandRequestJson = ScreenshotL10n.tr("Localizable", "home.detail.llm.expand_request_json", fallback: "Expand full request JSON")
          /// Expand full response JSON
          internal static let expandResponseJson = ScreenshotL10n.tr("Localizable", "home.detail.llm.expand_response_json", fallback: "Expand full response JSON")
          /// key_terms
          internal static let keyTerms = ScreenshotL10n.tr("Localizable", "home.detail.llm.key_terms", fallback: "key_terms")
          /// Pending Text
          internal static let pendingText = ScreenshotL10n.tr("Localizable", "home.detail.llm.pending_text", fallback: "Pending Text")
          /// polished
          internal static let polished = ScreenshotL10n.tr("Localizable", "home.detail.llm.polished", fallback: "polished")
          /// Request Summary
          internal static let requestJsonTitle = ScreenshotL10n.tr("Localizable", "home.detail.llm.request_json_title", fallback: "Request Summary")
          /// Human-readable content sent to the model
          internal static let requestSummarySubtitle = ScreenshotL10n.tr("Localizable", "home.detail.llm.request_summary_subtitle", fallback: "Human-readable content sent to the model")
          /// Response Summary
          internal static let responseJsonTitle = ScreenshotL10n.tr("Localizable", "home.detail.llm.response_json_title", fallback: "Response Summary")
          /// Structured result returned by the model
          internal static let responseSummarySubtitle = ScreenshotL10n.tr("Localizable", "home.detail.llm.response_summary_subtitle", fallback: "Structured result returned by the model")
          /// Returned Text
          internal static let returnedText = ScreenshotL10n.tr("Localizable", "home.detail.llm.returned_text", fallback: "Returned Text")
        }
        internal enum Meta {
          /// Application
          internal static let application = ScreenshotL10n.tr("Localizable", "home.detail.meta.application", fallback: "Application")
          /// Application used: %@
          internal static func applicationAccessibilityFormat(_ p1: Any) -> String {
            return ScreenshotL10n.tr("Localizable", "home.detail.meta.application_accessibility_format", String(describing: p1), fallback: "Application used: %@")
          }
          /// Speech Recognition
          internal static let asrProvider = ScreenshotL10n.tr("Localizable", "home.detail.meta.asr_provider", fallback: "Speech Recognition")
          /// Failed%@
          internal static func callFailureFormat(_ p1: Any) -> String {
            return ScreenshotL10n.tr("Localizable", "home.detail.meta.call_failure_format", String(describing: p1), fallback: "Failed%@")
          }
          /// Call Result
          internal static let callResult = ScreenshotL10n.tr("Localizable", "home.detail.meta.call_result", fallback: "Call Result")
          /// Success%@
          internal static func callSuccessFormat(_ p1: Any) -> String {
            return ScreenshotL10n.tr("Localizable", "home.detail.meta.call_success_format", String(describing: p1), fallback: "Success%@")
          }
          /// %d characters
          internal static func charactersFormat(_ p1: Int) -> String {
            return ScreenshotL10n.tr("Localizable", "home.detail.meta.characters_format", p1, fallback: "%d characters")
          }
          /// Correction Service
          internal static let correctionService = ScreenshotL10n.tr("Localizable", "home.detail.meta.correction_service", fallback: "Correction Service")
          /// %d chars/min
          internal static func cpmFormat(_ p1: Int) -> String {
            return ScreenshotL10n.tr("Localizable", "home.detail.meta.cpm_format", p1, fallback: "%d chars/min")
          }
          /// Created
          internal static let createdAt = ScreenshotL10n.tr("Localizable", "home.detail.meta.created_at", fallback: "Created")
          /// Duration
          internal static let duration = ScreenshotL10n.tr("Localizable", "home.detail.meta.duration", fallback: "Duration")
          /// Endpoint
          internal static let endpoint = ScreenshotL10n.tr("Localizable", "home.detail.meta.endpoint", fallback: "Endpoint")
          /// Generation Model
          internal static let generationModel = ScreenshotL10n.tr("Localizable", "home.detail.meta.generation_model", fallback: "Generation Model")
          /// Generation Service
          internal static let generationService = ScreenshotL10n.tr("Localizable", "home.detail.meta.generation_service", fallback: "Generation Service")
          /// Model
          internal static let model = ScreenshotL10n.tr("Localizable", "home.detail.meta.model", fallback: "Model")
          /// Not recorded
          internal static let notRecorded = ScreenshotL10n.tr("Localizable", "home.detail.meta.not_recorded", fallback: "Not recorded")
          /// Processing Speed
          internal static let processingSpeed = ScreenshotL10n.tr("Localizable", "home.detail.meta.processing_speed", fallback: "Processing Speed")
          /// Recognition Language
          internal static let recognitionLanguage = ScreenshotL10n.tr("Localizable", "home.detail.meta.recognition_language", fallback: "Recognition Language")
          /// Writing Style
          internal static let style = ScreenshotL10n.tr("Localizable", "home.detail.meta.style", fallback: "Writing Style")
          /// Text Correction
          internal static let textCorrection = ScreenshotL10n.tr("Localizable", "home.detail.meta.text_correction", fallback: "Text Correction")
          /// Text Length
          internal static let textLength = ScreenshotL10n.tr("Localizable", "home.detail.meta.text_length", fallback: "Text Length")
          /// Updated
          internal static let updatedAt = ScreenshotL10n.tr("Localizable", "home.detail.meta.updated_at", fallback: "Updated")
        }
        internal enum Pipeline {
          /// Inserted
          internal static let outputDone = ScreenshotL10n.tr("Localizable", "home.detail.pipeline.output_done", fallback: "Inserted")
        }
        internal enum RequestJson {
          /// Full request body was not saved in default privacy mode.
          internal static let redacted = ScreenshotL10n.tr("Localizable", "home.detail.request_json.redacted", fallback: "Full request body was not saved in default privacy mode.")
          /// Show Full Request
          internal static let show = ScreenshotL10n.tr("Localizable", "home.detail.request_json.show", fallback: "Show Full Request")
        }
        internal enum Status {
          /// Failed
          internal static let failed = ScreenshotL10n.tr("Localizable", "home.detail.status.failed", fallback: "Failed")
          /// Success
          internal static let success = ScreenshotL10n.tr("Localizable", "home.detail.status.success", fallback: "Success")
        }
        internal enum Style {
          /// Casual
          internal static let casual = ScreenshotL10n.tr("Localizable", "home.detail.style.casual", fallback: "Casual")
          /// Coding
          internal static let coding = ScreenshotL10n.tr("Localizable", "home.detail.style.coding", fallback: "Coding")
          /// Email
          internal static let email = ScreenshotL10n.tr("Localizable", "home.detail.style.email", fallback: "Email")
          /// Energetic
          internal static let energetic = ScreenshotL10n.tr("Localizable", "home.detail.style.energetic", fallback: "Energetic")
          /// Formal
          internal static let formal = ScreenshotL10n.tr("Localizable", "home.detail.style.formal", fallback: "Formal")
          /// Not selected
          internal static let notSelected = ScreenshotL10n.tr("Localizable", "home.detail.style.not_selected", fallback: "Not selected")
          /// Original
          internal static let original = ScreenshotL10n.tr("Localizable", "home.detail.style.original", fallback: "Original")
        }
        internal enum Subtitle {
          /// View voice intent, generated result, and processing details.
          internal static let agentCompose = ScreenshotL10n.tr("Localizable", "home.detail.subtitle.agent_compose", fallback: "View voice intent, generated result, and processing details.")
          /// View the voice command, assistant dispatch result, and failure details.
          internal static let agentDispatch = ScreenshotL10n.tr("Localizable", "home.detail.subtitle.agent_dispatch", fallback: "View the voice command, assistant dispatch result, and failure details.")
          /// Compare raw recognition with final text and inspect this processing pipeline.
          internal static let withTrace = ScreenshotL10n.tr("Localizable", "home.detail.subtitle.with_trace", fallback: "Compare raw recognition with final text and inspect this processing pipeline.")
          /// Compare raw recognition with final text; older records can be reprocessed to inspect the pipeline.
          internal static let withoutTrace = ScreenshotL10n.tr("Localizable", "home.detail.subtitle.without_trace", fallback: "Compare raw recognition with final text; older records can be reprocessed to inspect the pipeline.")
        }
        internal enum Tab {
          /// Context
          internal static let context = ScreenshotL10n.tr("Localizable", "home.detail.tab.context", fallback: "Context")
          /// Diagnostics
          internal static let diagnostic = ScreenshotL10n.tr("Localizable", "home.detail.tab.diagnostic", fallback: "Diagnostics")
          /// LLM Correction
          internal static let llm = ScreenshotL10n.tr("Localizable", "home.detail.tab.llm", fallback: "LLM Correction")
          /// Text Replacement
          internal static let voiceCorrection = ScreenshotL10n.tr("Localizable", "home.detail.tab.voice_correction", fallback: "Text Replacement")
        }
        internal enum Text {
          /// Text generated and inserted into the current input field.
          internal static let agentComposeFinalSubtitle = ScreenshotL10n.tr("Localizable", "home.detail.text.agent_compose_final_subtitle", fallback: "Text generated and inserted into the current input field.")
          /// Voice command sent to the terminal assistant.
          internal static let agentDispatchFinalSubtitle = ScreenshotL10n.tr("Localizable", "home.detail.text.agent_dispatch_final_subtitle", fallback: "Voice command sent to the terminal assistant.")
          /// Text finally inserted into the current app.
          internal static let dictationFinalSubtitle = ScreenshotL10n.tr("Localizable", "home.detail.text.dictation_final_subtitle", fallback: "Text finally inserted into the current app.")
          /// Saving updates history and learns text replacement from this edit.
          internal static let editSubtitle = ScreenshotL10n.tr("Localizable", "home.detail.text.edit_subtitle", fallback: "Saving updates history and learns text replacement from this edit.")
          /// Final Text
          internal static let finalTitle = ScreenshotL10n.tr("Localizable", "home.detail.text.final_title", fallback: "Final Text")
          /// Original text returned by speech recognition.
          internal static let rawSubtitle = ScreenshotL10n.tr("Localizable", "home.detail.text.raw_subtitle", fallback: "Original text returned by speech recognition.")
          /// Raw Recognition
          internal static let rawTitle = ScreenshotL10n.tr("Localizable", "home.detail.text.raw_title", fallback: "Raw Recognition")
          /// User instruction recognized from speech.
          internal static let voiceIntentSubtitle = ScreenshotL10n.tr("Localizable", "home.detail.text.voice_intent_subtitle", fallback: "User instruction recognized from speech.")
          /// Voice Intent
          internal static let voiceIntentTitle = ScreenshotL10n.tr("Localizable", "home.detail.text.voice_intent_title", fallback: "Voice Intent")
        }
        internal enum Title {
          /// Task Assistant Details
          internal static let agentCompose = ScreenshotL10n.tr("Localizable", "home.detail.title.agent_compose", fallback: "Task Assistant Details")
          /// AI Coding Details
          internal static let agentDispatch = ScreenshotL10n.tr("Localizable", "home.detail.title.agent_dispatch", fallback: "AI Coding Details")
          /// Transcription Details
          internal static let dictation = ScreenshotL10n.tr("Localizable", "home.detail.title.dictation", fallback: "Transcription Details")
        }
        internal enum Trace {
          /// Error returned by the API.
          internal static let apiErrorSubtitle = ScreenshotL10n.tr("Localizable", "home.detail.trace.api_error_subtitle", fallback: "Error returned by the API.")
          /// Call Failed
          internal static let callFailed = ScreenshotL10n.tr("Localizable", "home.detail.trace.call_failed", fallback: "Call Failed")
          /// Called
          internal static let called = ScreenshotL10n.tr("Localizable", "home.detail.trace.called", fallback: "Called")
          /// No response content
          internal static let emptyResponse = ScreenshotL10n.tr("Localizable", "home.detail.trace.empty_response", fallback: "No response content")
          /// Failure Reason
          internal static let failureReasonTitle = ScreenshotL10n.tr("Localizable", "home.detail.trace.failure_reason_title", fallback: "Failure Reason")
          /// Generation Process
          internal static let generationTitle = ScreenshotL10n.tr("Localizable", "home.detail.trace.generation_title", fallback: "Generation Process")
          /// Local post-processing
          internal static let localPostprocessing = ScreenshotL10n.tr("Localizable", "home.detail.trace.local_postprocessing", fallback: "Local post-processing")
          /// This Task Assistant record did not save the model call process, but the raw recognition and generated result are still available. Use Copy Result in the top-right.
          internal static let missingAgentCompose = ScreenshotL10n.tr("Localizable", "home.detail.trace.missing_agent_compose", fallback: "This Task Assistant record did not save the model call process, but the raw recognition and generated result are still available. Use Copy Result in the top-right.")
          /// This AI Coding record does not call the text correction model; the voice command and generated result are stored separately.
          internal static let missingAgentDispatch = ScreenshotL10n.tr("Localizable", "home.detail.trace.missing_agent_dispatch", fallback: "This AI Coding record does not call the text correction model; the voice command and generated result are stored separately.")
          /// This record has no model correction trace. Text correction may have been disabled, or the record was created before tracing was available. Click Reprocess in the top-right to inspect model calls, sent content, and returned results.
          internal static let missingDictation = ScreenshotL10n.tr("Localizable", "home.detail.trace.missing_dictation", fallback: "This record has no model correction trace. Text correction may have been disabled, or the record was created before tracing was available. Click Reprocess in the top-right to inspect model calls, sent content, and returned results.")
          /// Content sent to the model
          internal static let modelInput = ScreenshotL10n.tr("Localizable", "home.detail.trace.model_input", fallback: "Content sent to the model")
          /// Model Output
          internal static let modelOutputTitle = ScreenshotL10n.tr("Localizable", "home.detail.trace.model_output_title", fallback: "Model Output")
          /// Processing Pipeline
          internal static let pipelineTitle = ScreenshotL10n.tr("Localizable", "home.detail.trace.pipeline_title", fallback: "Processing Pipeline")
          /// Raw text returned by the model.
          internal static let rawModelOutputSubtitle = ScreenshotL10n.tr("Localizable", "home.detail.trace.raw_model_output_subtitle", fallback: "Raw text returned by the model.")
          /// What the user said
          internal static let userSpeech = ScreenshotL10n.tr("Localizable", "home.detail.trace.user_speech", fallback: "What the user said")
        }
        internal enum VoiceCorrection {
          /// Candidate Hits
          internal static let candidates = ScreenshotL10n.tr("Localizable", "home.detail.voice_correction.candidates", fallback: "Candidate Hits")
          /// Hit Evidence
          internal static let hitEvidence = ScreenshotL10n.tr("Localizable", "home.detail.voice_correction.hit_evidence", fallback: "Hit Evidence")
          /// Method
          internal static let method = ScreenshotL10n.tr("Localizable", "home.detail.voice_correction.method", fallback: "Method")
          /// %d more hidden
          internal static func moreFormat(_ p1: Int) -> String {
            return ScreenshotL10n.tr("Localizable", "home.detail.voice_correction.more_format", p1, fallback: "%d more hidden")
          }
          /// No text replacement rules matched
          internal static let noHits = ScreenshotL10n.tr("Localizable", "home.detail.voice_correction.no_hits", fallback: "No text replacement rules matched")
          /// Replacement Details
          internal static let replacementDetails = ScreenshotL10n.tr("Localizable", "home.detail.voice_correction.replacement_details", fallback: "Replacement Details")
          /// Applied Replacements
          internal static let replacements = ScreenshotL10n.tr("Localizable", "home.detail.voice_correction.replacements", fallback: "Applied Replacements")
          /// App: %@
          internal static func scopeApplicationFormat(_ p1: Any) -> String {
            return ScreenshotL10n.tr("Localizable", "home.detail.voice_correction.scope_application_format", String(describing: p1), fallback: "App: %@")
          }
          /// Global
          internal static let scopeGlobal = ScreenshotL10n.tr("Localizable", "home.detail.voice_correction.scope_global", fallback: "Global")
          /// Replaced %d
          internal static func statusAppliedFormat(_ p1: Int) -> String {
            return ScreenshotL10n.tr("Localizable", "home.detail.voice_correction.status_applied_format", p1, fallback: "Replaced %d")
          }
          /// %d hits, no rewrite
          internal static func statusCandidatesFormat(_ p1: Int) -> String {
            return ScreenshotL10n.tr("Localizable", "home.detail.voice_correction.status_candidates_format", p1, fallback: "%d hits, no rewrite")
          }
          /// Processing Failed
          internal static let statusFailed = ScreenshotL10n.tr("Localizable", "home.detail.voice_correction.status_failed", fallback: "Processing Failed")
          /// Checked, no hits
          internal static let statusNoHits = ScreenshotL10n.tr("Localizable", "home.detail.voice_correction.status_no_hits", fallback: "Checked, no hits")
          /// Text Replacement
          internal static let title = ScreenshotL10n.tr("Localizable", "home.detail.voice_correction.title", fallback: "Text Replacement")
        }
        internal enum Warning {
          /// Generation model call failed; the original speech is preserved for retry or copy in details.
          internal static let agentLlmFailed = ScreenshotL10n.tr("Localizable", "home.detail.warning.agent_llm_failed", fallback: "Generation model call failed; the original speech is preserved for retry or copy in details.")
          /// Reading current window context timed out, so processing continued with speech only.
          internal static let contextCollectionTimeout = ScreenshotL10n.tr("Localizable", "home.detail.warning.context_collection_timeout", fallback: "Reading current window context timed out, so processing continued with speech only.")
          /// Text correction was cancelled, so the raw recognition text was used directly.
          internal static let llmRefinementCancelled = ScreenshotL10n.tr("Localizable", "home.detail.warning.llm_refinement_cancelled", fallback: "Text correction was cancelled, so the raw recognition text was used directly.")
          /// Model call failed; the raw recognition text was preserved.
          internal static let llmRefinementFailed = ScreenshotL10n.tr("Localizable", "home.detail.warning.llm_refinement_failed", fallback: "Model call failed; the raw recognition text was preserved.")
          /// Screen recording permission is missing, so screenshot visual context could not be read; generation used only speech and readable text.
          internal static let screenRecordingNotAuthorized = ScreenshotL10n.tr("Localizable", "home.detail.warning.screen_recording_not_authorized", fallback: "Screen recording permission is missing, so screenshot visual context could not be read; generation used only speech and readable text.")
          /// Secure input was detected, so window content reading was skipped.
          internal static let secureTextFieldDetected = ScreenshotL10n.tr("Localizable", "home.detail.warning.secure_text_field_detected", fallback: "Secure input was detected, so window content reading was skipped.")
          /// The current model configuration does not support visual context.
          internal static let visionNotSupported = ScreenshotL10n.tr("Localizable", "home.detail.warning.vision_not_supported", fallback: "The current model configuration does not support visual context.")
          /// The current model configuration does not support screenshot visual context, so generation used only speech and readable text.
          internal static let visionNotSupportedAgent = ScreenshotL10n.tr("Localizable", "home.detail.warning.vision_not_supported_agent", fallback: "The current model configuration does not support screenshot visual context, so generation used only speech and readable text.")
          /// Reading screenshot visual context timed out; processing continued.
          internal static let visualFallbackTimeout = ScreenshotL10n.tr("Localizable", "home.detail.warning.visual_fallback_timeout", fallback: "Reading screenshot visual context timed out; processing continued.")
        }
        internal enum Warnings {
          /// Processing Warnings
          internal static let title = ScreenshotL10n.tr("Localizable", "home.detail.warnings.title", fallback: "Processing Warnings")
        }
      }
      internal enum Feedback {
        /// Asset content copied
        internal static let assetCopied = ScreenshotL10n.tr("Localizable", "home.feedback.asset_copied", fallback: "Asset content copied")
        /// Asset deleted
        internal static let assetDeleted = ScreenshotL10n.tr("Localizable", "home.feedback.asset_deleted", fallback: "Asset deleted")
        /// Asset not found.
        internal static let assetNotFound = ScreenshotL10n.tr("Localizable", "home.feedback.asset_not_found", fallback: "Asset not found.")
        /// Assets cleared
        internal static let assetsCleared = ScreenshotL10n.tr("Localizable", "home.feedback.assets_cleared", fallback: "Assets cleared")
        /// Deleted %d assets
        internal static func assetsDeletedFormat(_ p1: Int) -> String {
          return ScreenshotL10n.tr("Localizable", "home.feedback.assets_deleted_format", p1, fallback: "Deleted %d assets")
        }
        /// History record not found.
        internal static let historyNotFound = ScreenshotL10n.tr("Localizable", "home.feedback.history_not_found", fallback: "History record not found.")
        /// This asset has no copyable text.
        internal static let noCopyableText = ScreenshotL10n.tr("Localizable", "home.feedback.no_copyable_text", fallback: "This asset has no copyable text.")
      }
      internal enum Source {
        /// Task Assistant
        internal static let agentCompose = ScreenshotL10n.tr("Localizable", "home.source.agent_compose", fallback: "Task Assistant")
        /// Clipboard
        internal static let clipboard = ScreenshotL10n.tr("Localizable", "home.source.clipboard", fallback: "Clipboard")
        /// Voice
        internal static let dictation = ScreenshotL10n.tr("Localizable", "home.source.dictation", fallback: "Voice")
        /// None
        internal static let `none` = ScreenshotL10n.tr("Localizable", "home.source.none", fallback: "None")
        /// Screenshot
        internal static let screenshot = ScreenshotL10n.tr("Localizable", "home.source.screenshot", fallback: "Screenshot")
        /// Selection Assistant
        internal static let selectionAgent = ScreenshotL10n.tr("Localizable", "home.source.selection_agent", fallback: "Selection Assistant")
        /// Selection Summary
        internal static let selectionSummary = ScreenshotL10n.tr("Localizable", "home.source.selection_summary", fallback: "Selection Summary")
        /// Selection Translate
        internal static let selectionTranslation = ScreenshotL10n.tr("Localizable", "home.source.selection_translation", fallback: "Selection Translate")
      }
      internal enum Stats {
        /// %@ Added
        internal static func dateAddedFormat(_ p1: Any) -> String {
          return ScreenshotL10n.tr("Localizable", "home.stats.date_added_format", String(describing: p1), fallback: "%@ Added")
        }
        /// Reusable
        internal static let reusableAssets = ScreenshotL10n.tr("Localizable", "home.stats.reusable_assets", fallback: "Reusable")
        /// Added Today
        internal static let todayAdded = ScreenshotL10n.tr("Localizable", "home.stats.today_added", fallback: "Added Today")
        /// Total Assets
        internal static let totalAssets = ScreenshotL10n.tr("Localizable", "home.stats.total_assets", fallback: "Total Assets")
      }
    }
    internal enum Hotkey {
      internal enum Key {
        /// Left Command
        internal static let leftCommand = ScreenshotL10n.tr("Localizable", "hotkey.key.left_command", fallback: "Left Command")
        /// Left Control
        internal static let leftControl = ScreenshotL10n.tr("Localizable", "hotkey.key.left_control", fallback: "Left Control")
        /// Left Option
        internal static let leftOption = ScreenshotL10n.tr("Localizable", "hotkey.key.left_option", fallback: "Left Option")
        /// Left Shift
        internal static let leftShift = ScreenshotL10n.tr("Localizable", "hotkey.key.left_shift", fallback: "Left Shift")
        /// ===== Hotkey =====
        internal static let rightCommand = ScreenshotL10n.tr("Localizable", "hotkey.key.right_command", fallback: "Right Command")
        /// Right Control
        internal static let rightControl = ScreenshotL10n.tr("Localizable", "hotkey.key.right_control", fallback: "Right Control")
        /// Right Option
        internal static let rightOption = ScreenshotL10n.tr("Localizable", "hotkey.key.right_option", fallback: "Right Option")
        /// Right Shift
        internal static let rightShift = ScreenshotL10n.tr("Localizable", "hotkey.key.right_shift", fallback: "Right Shift")
        /// Key %ld
        internal static func unknownFormat(_ p1: Int) -> String {
          return ScreenshotL10n.tr("Localizable", "hotkey.key.unknown_format", p1, fallback: "Key %ld")
        }
      }
      internal enum Keycap {
        /// ⌘
        internal static let command = ScreenshotL10n.tr("Localizable", "hotkey.keycap.command", fallback: "⌘")
        /// ⌃
        internal static let leftControl = ScreenshotL10n.tr("Localizable", "hotkey.keycap.left_control", fallback: "⌃")
        /// ⌥
        internal static let leftOption = ScreenshotL10n.tr("Localizable", "hotkey.keycap.left_option", fallback: "⌥")
        /// ⇧
        internal static let leftShift = ScreenshotL10n.tr("Localizable", "hotkey.keycap.left_shift", fallback: "⇧")
        /// ⌃
        internal static let rightControl = ScreenshotL10n.tr("Localizable", "hotkey.keycap.right_control", fallback: "⌃")
        /// ⌥
        internal static let rightOption = ScreenshotL10n.tr("Localizable", "hotkey.keycap.right_option", fallback: "⌥")
        /// ⇧
        internal static let rightShift = ScreenshotL10n.tr("Localizable", "hotkey.keycap.right_shift", fallback: "⇧")
      }
    }
    internal enum Hud {
      /// No available task assistant
      internal static let noAgentAvailable = ScreenshotL10n.tr("Localizable", "hud.no_agent_available", fallback: "No available task assistant")
      /// Press %@ %@
      internal static func selectionActionButtonTooltipFormat(_ p1: Any, _ p2: Any) -> String {
        return ScreenshotL10n.tr("Localizable", "hud.selection_action_button_tooltip_format", String(describing: p1), String(describing: p2), fallback: "Press %@ %@")
      }
      internal enum AgentCompose {
        /// Context unavailable; dictating only
        internal static let contextUnavailable = ScreenshotL10n.tr("Localizable", "hud.agent_compose.context_unavailable", fallback: "Context unavailable; dictating only")
        /// Copied
        internal static let copied = ScreenshotL10n.tr("Localizable", "hud.agent_compose.copied", fallback: "Copied")
        /// Copied to clipboard
        internal static let copiedDetail = ScreenshotL10n.tr("Localizable", "hud.agent_compose.copied_detail", fallback: "Copied to clipboard")
        /// Generating
        internal static let generating = ScreenshotL10n.tr("Localizable", "hud.agent_compose.generating", fallback: "Generating")
        /// Generating text...
        internal static let generatingDetail = ScreenshotL10n.tr("Localizable", "hud.agent_compose.generating_detail", fallback: "Generating text...")
        /// Inserted
        internal static let inserted = ScreenshotL10n.tr("Localizable", "hud.agent_compose.inserted", fallback: "Inserted")
        /// Inserted to current input field
        internal static let insertedDetail = ScreenshotL10n.tr("Localizable", "hud.agent_compose.inserted_detail", fallback: "Inserted to current input field")
        /// Reading window context...
        internal static let readingWindowDetail = ScreenshotL10n.tr("Localizable", "hud.agent_compose.reading_window_detail", fallback: "Reading window context...")
        /// Read Window
        internal static let readingWindowTitle = ScreenshotL10n.tr("Localizable", "hud.agent_compose.reading_window_title", fallback: "Read Window")
        /// Transcribing
        internal static let transcribing = ScreenshotL10n.tr("Localizable", "hud.agent_compose.transcribing", fallback: "Transcribing")
        /// Recognizing speech...
        internal static let transcribingDetail = ScreenshotL10n.tr("Localizable", "hud.agent_compose.transcribing_detail", fallback: "Recognizing speech...")
      }
      internal enum Badge {
        /// Exact Send
        internal static let exactSend = ScreenshotL10n.tr("Localizable", "hud.badge.exact_send", fallback: "Exact Send")
      }
      internal enum Confirmation {
        /// Press 1-9 to select task assistant, press 0 to write directly to current input field
        internal static let footerHint = ScreenshotL10n.tr("Localizable", "hud.confirmation.footer_hint", fallback: "Press 1-9 to select task assistant, press 0 to write directly to current input field")
      }
      internal enum Detail {
        /// %@, command retained: %@
        internal static func failureWithRetained(_ p1: Any, _ p2: Any) -> String {
          return ScreenshotL10n.tr("Localizable", "hud.detail.failure_with_retained", String(describing: p1), String(describing: p2), fallback: "%@, command retained: %@")
        }
        /// Listening by %@
        internal static func listeningAgents(_ p1: Any) -> String {
          return ScreenshotL10n.tr("Localizable", "hud.detail.listening_agents", String(describing: p1), fallback: "Listening by %@")
        }
      }
      internal enum Feedback {
        /// Generated and copied to clipboard
        internal static let agentComposeCopied = ScreenshotL10n.tr("Localizable", "hud.feedback.agent_compose_copied", fallback: "Generated and copied to clipboard")
        /// Generated and inserted to current input field
        internal static let agentComposeInjected = ScreenshotL10n.tr("Localizable", "hud.feedback.agent_compose_injected", fallback: "Generated and inserted to current input field")
        /// Clipboard image OCR processing
        internal static let clipboardImageOcrProcessing = ScreenshotL10n.tr("Localizable", "hud.feedback.clipboard_image_ocr_processing", fallback: "Clipboard image OCR processing")
        /// Image text recognition failed: %@
        internal static func clipboardOcrFailedFormat(_ p1: Any) -> String {
          return ScreenshotL10n.tr("Localizable", "hud.feedback.clipboard_ocr_failed_format", String(describing: p1), fallback: "Image text recognition failed: %@")
        }
        /// %@, command retained
        internal static func commandRetainedFormat(_ p1: Any) -> String {
          return ScreenshotL10n.tr("Localizable", "hud.feedback.command_retained_format", String(describing: p1), fallback: "%@, command retained")
        }
        /// Generation completed, but copy failed. Click to copy manually.
        internal static let copyFailedPrompt = ScreenshotL10n.tr("Localizable", "hud.feedback.copy_failed_prompt", fallback: "Generation completed, but copy failed. Click to copy manually.")
        /// Image text recognized and pasted
        internal static let imageTextCopied = ScreenshotL10n.tr("Localizable", "hud.feedback.image_text_copied", fallback: "Image text recognized and pasted")
        /// Failed to paste recognized text; result retained. Click to copy.
        internal static let imageTextPasteFailedRetainCopy = ScreenshotL10n.tr("Localizable", "hud.feedback.image_text_paste_failed_retain_copy", fallback: "Failed to paste recognized text; result retained. Click to copy.")
        /// Input failed; content copied.
        internal static let inputFailedCopied = ScreenshotL10n.tr("Localizable", "hud.feedback.input_failed_copied", fallback: "Input failed; content copied.")
        /// Manual copy failed, please try again later.
        internal static let manualCopyFailed = ScreenshotL10n.tr("Localizable", "hud.feedback.manual_copy_failed", fallback: "Manual copy failed, please try again later.")
        /// Result manually copied
        internal static let manualCopySucceeded = ScreenshotL10n.tr("Localizable", "hud.feedback.manual_copy_succeeded", fallback: "Result manually copied")
        /// No recognizable image in clipboard
        internal static let noClipboardImage = ScreenshotL10n.tr("Localizable", "hud.feedback.no_clipboard_image", fallback: "No recognizable image in clipboard")
        /// No copyable result
        internal static let noCopyableResult = ScreenshotL10n.tr("Localizable", "hud.feedback.no_copyable_result", fallback: "No copyable result")
        /// No last result to paste
        internal static let noLastResultToPaste = ScreenshotL10n.tr("Localizable", "hud.feedback.no_last_result_to_paste", fallback: "No last result to paste")
        /// Paste failed; result retained. Click to copy.
        internal static let pasteFailedRetainCopy = ScreenshotL10n.tr("Localizable", "hud.feedback.paste_failed_retain_copy", fallback: "Paste failed; result retained. Click to copy.")
        /// Last result pasted
        internal static let pasteLastResultSucceeded = ScreenshotL10n.tr("Localizable", "hud.feedback.paste_last_result_succeeded", fallback: "Last result pasted")
        /// Accessibility permission denied; content copied.
        internal static let permissionDeniedCopied = ScreenshotL10n.tr("Localizable", "hud.feedback.permission_denied_copied", fallback: "Accessibility permission denied; content copied.")
        /// Sent to %@
        internal static func sentToAgentFormat(_ p1: Any) -> String {
          return ScreenshotL10n.tr("Localizable", "hud.feedback.sent_to_agent_format", String(describing: p1), fallback: "Sent to %@")
        }
        /// Target window changed; content copied.
        internal static let targetWindowChangedCopied = ScreenshotL10n.tr("Localizable", "hud.feedback.target_window_changed_copied", fallback: "Target window changed; content copied.")
        /// %@, click to undo
        internal static func undoPromptFormat(_ p1: Any) -> String {
          return ScreenshotL10n.tr("Localizable", "hud.feedback.undo_prompt_format", String(describing: p1), fallback: "%@, click to undo")
        }
      }
      internal enum Label {
        /// Confidence
        internal static let confidence = ScreenshotL10n.tr("Localizable", "hud.label.confidence", fallback: "Confidence")
      }
      internal enum Message {
        /// Tip
        internal static let info = ScreenshotL10n.tr("Localizable", "hud.message.info", fallback: "Tip")
        /// Preparing...
        internal static let prepare = ScreenshotL10n.tr("Localizable", "hud.message.prepare", fallback: "Preparing...")
        /// Processing...
        internal static let processing = ScreenshotL10n.tr("Localizable", "hud.message.processing", fallback: "Processing...")
        /// Recognizing...
        internal static let recognizing = ScreenshotL10n.tr("Localizable", "hud.message.recognizing", fallback: "Recognizing...")
        /// Success
        internal static let success = ScreenshotL10n.tr("Localizable", "hud.message.success", fallback: "Success")
        /// Writing...
        internal static let writing = ScreenshotL10n.tr("Localizable", "hud.message.writing", fallback: "Writing...")
      }
      internal enum Output {
        /// Write to current input field
        internal static let defaultLabel = ScreenshotL10n.tr("Localizable", "hud.output.default_label", fallback: "Write to current input field")
      }
      internal enum Prompt {
        /// Speak out the task for the task assistant.
        internal static let dictateToAgent = ScreenshotL10n.tr("Localizable", "hud.prompt.dictate_to_agent", fallback: "Speak out the task for the task assistant.")
      }
      internal enum SelectionAction {
        /// Close
        internal static let close = ScreenshotL10n.tr("Localizable", "hud.selection_action.close", fallback: "Close")
        /// Selection Action
        internal static let title = ScreenshotL10n.tr("Localizable", "hud.selection_action.title", fallback: "Selection Action")
      }
      internal enum Status {
        /// Need confirmation
        internal static let confirmation = ScreenshotL10n.tr("Localizable", "hud.status.confirmation", fallback: "Need confirmation")
        /// Dictating
        internal static let dictating = ScreenshotL10n.tr("Localizable", "hud.status.dictating", fallback: "Dictating")
        /// Refining
        internal static let refining = ScreenshotL10n.tr("Localizable", "hud.status.refining", fallback: "Refining")
      }
      internal enum TextResult {
        /// ===== HUD =====
        internal static let close = ScreenshotL10n.tr("Localizable", "hud.text_result.close", fallback: "Close")
        /// Reading
        internal static let reading = ScreenshotL10n.tr("Localizable", "hud.text_result.reading", fallback: "Reading")
        /// Stop Reading
        internal static let stopReading = ScreenshotL10n.tr("Localizable", "hud.text_result.stop_reading", fallback: "Stop Reading")
      }
      internal enum Title {
        /// Using clipboard fallback
        internal static let clipboardFallback = ScreenshotL10n.tr("Localizable", "hud.title.clipboard_fallback", fallback: "Using clipboard fallback")
        /// Need confirmation
        internal static let confirmation = ScreenshotL10n.tr("Localizable", "hud.title.confirmation", fallback: "Need confirmation")
        /// Exact Send by %@
        internal static func exact(_ p1: Any) -> String {
          return ScreenshotL10n.tr("Localizable", "hud.title.exact", String(describing: p1), fallback: "Exact Send by %@")
        }
        /// Dispatch failed
        internal static let failure = ScreenshotL10n.tr("Localizable", "hud.title.failure", fallback: "Dispatch failed")
        /// Paste then write
        internal static let fallbackInput = ScreenshotL10n.tr("Localizable", "hud.title.fallback_input", fallback: "Paste then write")
        /// Listening
        internal static let listening = ScreenshotL10n.tr("Localizable", "hud.title.listening", fallback: "Listening")
        /// Sent to %@
        internal static func sent(_ p1: Any) -> String {
          return ScreenshotL10n.tr("Localizable", "hud.title.sent", String(describing: p1), fallback: "Sent to %@")
        }
      }
      internal enum Transcription {
        /// Listening...
        internal static let emptyListeningText = ScreenshotL10n.tr("Localizable", "hud.transcription.empty_listening_text", fallback: "Listening...")
        /// Recognizing text...
        internal static let emptyRefinementText = ScreenshotL10n.tr("Localizable", "hud.transcription.empty_refinement_text", fallback: "Recognizing text...")
      }
    }
    internal enum I18n {
      internal enum Smoke {
        /// ===== Smoke key (framework stage, removed after full migration) =====
        internal static let title = ScreenshotL10n.tr("Localizable", "i18n.smoke.title", fallback: "Localization smoke")
      }
    }
    internal enum InstalledAppSelector {
      /// Search app name or Bundle ID...
      internal static let searchPlaceholder = ScreenshotL10n.tr("Localizable", "installed_app_selector.search_placeholder", fallback: "Search app name or Bundle ID...")
    }
    internal enum Llm {
      internal enum Connection {
        /// ===== LLM =====
        internal static let success = ScreenshotL10n.tr("Localizable", "llm.connection.success", fallback: "LLM connection test passed.")
      }
      internal enum Refiner {
        internal enum Error {
          /// LLM API error (%d): %@
          internal static func apiErrorFormat(_ p1: Int, _ p2: Any) -> String {
            return ScreenshotL10n.tr("Localizable", "llm.refiner.error.api_error_format", p1, String(describing: p2), fallback: "LLM API error (%d): %@")
          }
          /// LLM request failed with HTTP status %d.
          internal static func httpErrorFormat(_ p1: Int) -> String {
            return ScreenshotL10n.tr("Localizable", "llm.refiner.error.http_error_format", p1, fallback: "LLM request failed with HTTP status %d.")
          }
          /// Unable to build LLM request.
          internal static let invalidRequestBody = ScreenshotL10n.tr("Localizable", "llm.refiner.error.invalid_request_body", fallback: "Unable to build LLM request.")
          /// Invalid response from LLM service.
          internal static let invalidResponse = ScreenshotL10n.tr("Localizable", "llm.refiner.error.invalid_response", fallback: "Invalid response from LLM service.")
          /// Invalid LLM base URL.
          internal static let invalidUrl = ScreenshotL10n.tr("Localizable", "llm.refiner.error.invalid_url", fallback: "Invalid LLM base URL.")
          /// LLM network error: %@
          internal static func networkErrorFormat(_ p1: Any) -> String {
            return ScreenshotL10n.tr("Localizable", "llm.refiner.error.network_error_format", String(describing: p1), fallback: "LLM network error: %@")
          }
          /// LLM is not configured.
          internal static let notConfigured = ScreenshotL10n.tr("Localizable", "llm.refiner.error.not_configured", fallback: "LLM is not configured.")
        }
      }
      internal enum TextTransform {
        /// Please configure a model in Settings first.
        internal static let unavailableMessage = ScreenshotL10n.tr("Localizable", "llm.text_transform.unavailable_message", fallback: "Please configure a model in Settings first.")
      }
    }
    internal enum Menu {
      internal enum Main {
        /// ===== Menu =====
        internal static let about = ScreenshotL10n.tr("Localizable", "menu.main.about", fallback: "About VoxFlow")
        /// Check for Updates
        internal static let checkUpdates = ScreenshotL10n.tr("Localizable", "menu.main.check_updates", fallback: "Check for Updates")
        /// Copy
        internal static let copy = ScreenshotL10n.tr("Localizable", "menu.main.copy", fallback: "Copy")
        /// Cut
        internal static let cut = ScreenshotL10n.tr("Localizable", "menu.main.cut", fallback: "Cut")
        /// Edit
        internal static let edit = ScreenshotL10n.tr("Localizable", "menu.main.edit", fallback: "Edit")
        /// Hide VoxFlow
        internal static let hide = ScreenshotL10n.tr("Localizable", "menu.main.hide", fallback: "Hide VoxFlow")
        /// Hide Others
        internal static let hideOthers = ScreenshotL10n.tr("Localizable", "menu.main.hide_others", fallback: "Hide Others")
        /// Paste
        internal static let paste = ScreenshotL10n.tr("Localizable", "menu.main.paste", fallback: "Paste")
        /// Quit VoxFlow
        internal static let quit = ScreenshotL10n.tr("Localizable", "menu.main.quit", fallback: "Quit VoxFlow")
        /// Redo
        internal static let redo = ScreenshotL10n.tr("Localizable", "menu.main.redo", fallback: "Redo")
        /// Select All
        internal static let selectAll = ScreenshotL10n.tr("Localizable", "menu.main.select_all", fallback: "Select All")
        /// Undo
        internal static let undo = ScreenshotL10n.tr("Localizable", "menu.main.undo", fallback: "Undo")
      }
      internal enum ProviderTag {
        /// Accurate
        internal static let accurate = ScreenshotL10n.tr("Localizable", "menu.provider_tag.accurate", fallback: "Accurate")
        /// Chinese
        internal static let chinese = ScreenshotL10n.tr("Localizable", "menu.provider_tag.chinese", fallback: "Chinese")
        /// CoreML
        internal static let coreml = ScreenshotL10n.tr("Localizable", "menu.provider_tag.coreml", fallback: "CoreML")
        /// English
        internal static let english = ScreenshotL10n.tr("Localizable", "menu.provider_tag.english", fallback: "English")
        /// Fast
        internal static let fast = ScreenshotL10n.tr("Localizable", "menu.provider_tag.fast", fallback: "Fast")
        /// Multilingual
        internal static let multilingual = ScreenshotL10n.tr("Localizable", "menu.provider_tag.multilingual", fallback: "Multilingual")
        /// Non-Streaming
        internal static let nonStreaming = ScreenshotL10n.tr("Localizable", "menu.provider_tag.non_streaming", fallback: "Non-Streaming")
        /// Offline
        internal static let offline = ScreenshotL10n.tr("Localizable", "menu.provider_tag.offline", fallback: "Offline")
        /// Online
        internal static let online = ScreenshotL10n.tr("Localizable", "menu.provider_tag.online", fallback: "Online")
        /// Streaming
        internal static let streaming = ScreenshotL10n.tr("Localizable", "menu.provider_tag.streaming", fallback: "Streaming")
      }
      internal enum Status {
        /// ASR Models
        internal static let asrModel = ScreenshotL10n.tr("Localizable", "menu.status.asr_model", fallback: "ASR Models")
        /// Check Permissions
        internal static let checkPermissions = ScreenshotL10n.tr("Localizable", "menu.status.check_permissions", fallback: "Check Permissions")
        /// GitHub
        internal static let github = ScreenshotL10n.tr("Localizable", "menu.status.github", fallback: "GitHub")
        /// Language
        internal static let language = ScreenshotL10n.tr("Localizable", "menu.status.language", fallback: "Language")
        /// LLM Service
        internal static let llmService = ScreenshotL10n.tr("Localizable", "menu.status.llm_service", fallback: "LLM Service")
        /// No LLM model service configured
        internal static let llmServiceUnavailable = ScreenshotL10n.tr("Localizable", "menu.status.llm_service_unavailable", fallback: "No LLM model service configured")
        /// Open Workbench
        internal static let openWorkbench = ScreenshotL10n.tr("Localizable", "menu.status.open_workbench", fallback: "Open Workbench")
        /// Quit VoxFlow
        internal static let quit = ScreenshotL10n.tr("Localizable", "menu.status.quit", fallback: "Quit VoxFlow")
        /// Refining with Smart Correction
        internal static let refining = ScreenshotL10n.tr("Localizable", "menu.status.refining", fallback: "Refining with Smart Correction")
        /// Selection Action
        internal static let selectionAction = ScreenshotL10n.tr("Localizable", "menu.status.selection_action", fallback: "Selection Action")
        /// Settings
        internal static let settings = ScreenshotL10n.tr("Localizable", "menu.status.settings", fallback: "Settings")
        /// Translation Model
        internal static let translationModel = ScreenshotL10n.tr("Localizable", "menu.status.translation_model", fallback: "Translation Model")
        /// TTS Model
        internal static let ttsModel = ScreenshotL10n.tr("Localizable", "menu.status.tts_model", fallback: "TTS Model")
        internal enum Capability {
          /// Not configured
          internal static let notConfigured = ScreenshotL10n.tr("Localizable", "menu.status.capability.not_configured", fallback: "Not configured")
          /// Not downloaded
          internal static let notDownloaded = ScreenshotL10n.tr("Localizable", "menu.status.capability.not_downloaded", fallback: "Not downloaded")
        }
      }
      internal enum VoiceAction {
        /// Task Assistant
        internal static let agentCompose = ScreenshotL10n.tr("Localizable", "menu.voice_action.agent_compose", fallback: "Task Assistant")
        /// Task Dispatch
        internal static let agentDispatch = ScreenshotL10n.tr("Localizable", "menu.voice_action.agent_dispatch", fallback: "Task Dispatch")
        /// ===== Menu =====
        internal static let dictation = ScreenshotL10n.tr("Localizable", "menu.voice_action.dictation", fallback: "Dictation")
      }
    }
    internal enum Model {
      internal enum Capability {
        /// Local model download completed
        internal static let actionDownloadCompleted = ScreenshotL10n.tr("Localizable", "model.capability.action_download_completed", fallback: "Local model download completed")
        /// Use built-in model
        internal static let actionSwitchBuiltinModel = ScreenshotL10n.tr("Localizable", "model.capability.action_switch_builtin_model", fallback: "Use built-in model")
        /// Open model settings
        internal static let actionSwitchModelConfig = ScreenshotL10n.tr("Localizable", "model.capability.action_switch_model_config", fallback: "Open model settings")
        /// Please configure an AI model service in Settings first
        internal static let configRequiredError = ScreenshotL10n.tr("Localizable", "model.capability.config_required_error", fallback: "Please configure an AI model service in Settings first")
        /// Using
        internal static let currentUsing = ScreenshotL10n.tr("Localizable", "model.capability.current_using", fallback: "Using")
        /// Download
        internal static let downloadButton = ScreenshotL10n.tr("Localizable", "model.capability.download_button", fallback: "Download")
        /// Downloading...
        internal static let downloading = ScreenshotL10n.tr("Localizable", "model.capability.downloading", fallback: "Downloading...")
        /// ===== Capability models =====
        internal static let recommended = ScreenshotL10n.tr("Localizable", "model.capability.recommended", fallback: "Recommended")
        /// Not downloaded
        internal static let statusNotDownloaded = ScreenshotL10n.tr("Localizable", "model.capability.status_not_downloaded", fallback: "Not downloaded")
        /// Ready
        internal static let statusReady = ScreenshotL10n.tr("Localizable", "model.capability.status_ready", fallback: "Ready")
        /// Not configured
        internal static let statusUnconfigured = ScreenshotL10n.tr("Localizable", "model.capability.status_unconfigured", fallback: "Not configured")
        /// Falls back to original text when unavailable
        internal static let translationLlmConfigFallback = ScreenshotL10n.tr("Localizable", "model.capability.translation_llm_config_fallback", fallback: "Falls back to original text when unavailable")
        /// Low memory
        internal static let translationLlmConfigMemory = ScreenshotL10n.tr("Localizable", "model.capability.translation_llm_config_memory", fallback: "Low memory")
        /// AI Model Configuration
        internal static let translationLlmConfigName = ScreenshotL10n.tr("Localizable", "model.capability.translation_llm_config_name", fallback: "AI Model Configuration")
        /// Cloud
        internal static let translationLlmConfigSize = ScreenshotL10n.tr("Localizable", "model.capability.translation_llm_config_size", fallback: "Cloud")
        /// Use your configured AI model service
        internal static let translationLlmConfigSubtitle = ScreenshotL10n.tr("Localizable", "model.capability.translation_llm_config_subtitle", fallback: "Use your configured AI model service")
        /// Falls back to system translation or an AI model
        internal static let translationMadladFallback = ScreenshotL10n.tr("Localizable", "model.capability.translation_madlad_fallback", fallback: "Falls back to system translation or an AI model")
        /// Higher memory
        internal static let translationMadladMemory = ScreenshotL10n.tr("Localizable", "model.capability.translation_madlad_memory", fallback: "Higher memory")
        /// 3.1 GB
        internal static let translationMadladSize = ScreenshotL10n.tr("Localizable", "model.capability.translation_madlad_size", fallback: "3.1 GB")
        /// Local multilingual translation model
        internal static let translationMadladSubtitle = ScreenshotL10n.tr("Localizable", "model.capability.translation_madlad_subtitle", fallback: "Local multilingual translation model")
        /// A configured AI model can be used when system translation fails
        internal static let translationSystemDefaultFallback = ScreenshotL10n.tr("Localizable", "model.capability.translation_system_default_fallback", fallback: "A configured AI model can be used when system translation fails")
        /// Low memory
        internal static let translationSystemDefaultMemory = ScreenshotL10n.tr("Localizable", "model.capability.translation_system_default_memory", fallback: "Low memory")
        /// System Default
        internal static let translationSystemDefaultName = ScreenshotL10n.tr("Localizable", "model.capability.translation_system_default_name", fallback: "System Default")
        /// Built in
        internal static let translationSystemDefaultSize = ScreenshotL10n.tr("Localizable", "model.capability.translation_system_default_size", fallback: "Built in")
        /// Use Apple system translation when available
        internal static let translationSystemDefaultSubtitle = ScreenshotL10n.tr("Localizable", "model.capability.translation_system_default_subtitle", fallback: "Use Apple system translation when available")
        /// Falls back to Kokoro or the system voice
        internal static let ttsCosyFallback = ScreenshotL10n.tr("Localizable", "model.capability.tts_cosy_fallback", fallback: "Falls back to Kokoro or the system voice")
        /// Higher memory
        internal static let ttsCosyMemory = ScreenshotL10n.tr("Localizable", "model.capability.tts_cosy_memory", fallback: "Higher memory")
        /// Natural voice synthesis model
        internal static let ttsCosySubtitle = ScreenshotL10n.tr("Localizable", "model.capability.tts_cosy_subtitle", fallback: "Natural voice synthesis model")
        /// Falls back to the system voice
        internal static let ttsKokoroFallback = ScreenshotL10n.tr("Localizable", "model.capability.tts_kokoro_fallback", fallback: "Falls back to the system voice")
        /// Low memory
        internal static let ttsKokoroMemory = ScreenshotL10n.tr("Localizable", "model.capability.tts_kokoro_memory", fallback: "Low memory")
        /// Lightweight local TTS model
        internal static let ttsKokoroSubtitle = ScreenshotL10n.tr("Localizable", "model.capability.tts_kokoro_subtitle", fallback: "Lightweight local TTS model")
        /// Falls back to Kokoro or the system voice
        internal static let ttsQwen3Fallback = ScreenshotL10n.tr("Localizable", "model.capability.tts_qwen3_fallback", fallback: "Falls back to Kokoro or the system voice")
        /// Higher memory
        internal static let ttsQwen3Memory = ScreenshotL10n.tr("Localizable", "model.capability.tts_qwen3_memory", fallback: "Higher memory")
        /// Higher quality multilingual speech synthesis
        internal static let ttsQwen3Subtitle = ScreenshotL10n.tr("Localizable", "model.capability.tts_qwen3_subtitle", fallback: "Higher quality multilingual speech synthesis")
        /// Falls back to the system voice
        internal static let ttsSystemDefaultFallback = ScreenshotL10n.tr("Localizable", "model.capability.tts_system_default_fallback", fallback: "Falls back to the system voice")
        /// Low memory
        internal static let ttsSystemDefaultMemory = ScreenshotL10n.tr("Localizable", "model.capability.tts_system_default_memory", fallback: "Low memory")
        /// System Default
        internal static let ttsSystemDefaultName = ScreenshotL10n.tr("Localizable", "model.capability.tts_system_default_name", fallback: "System Default")
        /// Built in
        internal static let ttsSystemDefaultSize = ScreenshotL10n.tr("Localizable", "model.capability.tts_system_default_size", fallback: "Built in")
        /// Use the macOS built-in speech voice
        internal static let ttsSystemDefaultSubtitle = ScreenshotL10n.tr("Localizable", "model.capability.tts_system_default_subtitle", fallback: "Use the macOS built-in speech voice")
      }
      internal enum Download {
        /// Model size %@
        internal static func sizeFormat(_ p1: Any) -> String {
          return ScreenshotL10n.tr("Localizable", "model.download.size_format", String(describing: p1), fallback: "Model size %@")
        }
        /// download size unknown
        internal static let sizeUnknown = ScreenshotL10n.tr("Localizable", "model.download.size_unknown", fallback: "download size unknown")
      }
      internal enum LlmProvider {
        /// Connection test succeeded
        internal static let actionConnectionSuccess = ScreenshotL10n.tr("Localizable", "model.llm_provider.action_connection_success", fallback: "Connection test succeeded")
        /// Provider deleted
        internal static let actionDeleteSuccess = ScreenshotL10n.tr("Localizable", "model.llm_provider.action_delete_success", fallback: "Provider deleted")
        /// Selected global model %@
        internal static func actionModelSelectedFormat(_ p1: Any) -> String {
          return ScreenshotL10n.tr("Localizable", "model.llm_provider.action_model_selected_format", String(describing: p1), fallback: "Selected global model %@")
        }
        /// Model list refreshed
        internal static let actionRefreshModelsSuccess = ScreenshotL10n.tr("Localizable", "model.llm_provider.action_refresh_models_success", fallback: "Model list refreshed")
        /// Model provider saved
        internal static let actionSaveSuccess = ScreenshotL10n.tr("Localizable", "model.llm_provider.action_save_success", fallback: "Model provider saved")
        /// Set as global default model
        internal static let actionSetDefault = ScreenshotL10n.tr("Localizable", "model.llm_provider.action_set_default", fallback: "Set as global default model")
        /// Add provider
        internal static let addButton = ScreenshotL10n.tr("Localizable", "model.llm_provider.add_button", fallback: "Add provider")
        /// Add an OpenAI-compatible provider
        internal static let addServiceHelp = ScreenshotL10n.tr("Localizable", "model.llm_provider.add_service_help", fallback: "Add an OpenAI-compatible provider")
        /// Hide API key
        internal static let apiKeyHide = ScreenshotL10n.tr("Localizable", "model.llm_provider.api_key_hide", fallback: "Hide API key")
        /// Show API key
        internal static let apiKeyShow = ScreenshotL10n.tr("Localizable", "model.llm_provider.api_key_show", fallback: "Show API key")
        /// Close
        internal static let close = ScreenshotL10n.tr("Localizable", "model.llm_provider.close", fallback: "Close")
        /// Current
        internal static let currentUse = ScreenshotL10n.tr("Localizable", "model.llm_provider.current_use", fallback: "Current")
        /// Delete
        internal static let delete = ScreenshotL10n.tr("Localizable", "model.llm_provider.delete", fallback: "Delete")
        /// Edit
        internal static let edit = ScreenshotL10n.tr("Localizable", "model.llm_provider.edit", fallback: "Edit")
        /// No model providers yet
        internal static let emptyState = ScreenshotL10n.tr("Localizable", "model.llm_provider.empty_state", fallback: "No model providers yet")
        /// Enter an API key
        internal static let errorApiKeyRequired = ScreenshotL10n.tr("Localizable", "model.llm_provider.error_api_key_required", fallback: "Enter an API key")
        /// API key is too short.
        internal static let errorApiKeyTooShort = ScreenshotL10n.tr("Localizable", "model.llm_provider.error_api_key_too_short", fallback: "API key is too short.")
        /// Enter a valid HTTP or HTTPS URL
        internal static let errorBaseUrlInvalid = ScreenshotL10n.tr("Localizable", "model.llm_provider.error_base_url_invalid", fallback: "Enter a valid HTTP or HTTPS URL")
        /// Enter a model name.
        internal static let errorModelNameRequired = ScreenshotL10n.tr("Localizable", "model.llm_provider.error_model_name_required", fallback: "Enter a model name.")
        /// Enter a model name
        internal static let errorModelRequired = ScreenshotL10n.tr("Localizable", "model.llm_provider.error_model_required", fallback: "Enter a model name")
        /// Enter a name
        internal static let errorNameRequired = ScreenshotL10n.tr("Localizable", "model.llm_provider.error_name_required", fallback: "Enter a name")
        /// Provider not found.
        internal static let errorNotFound = ScreenshotL10n.tr("Localizable", "model.llm_provider.error_not_found", fallback: "Provider not found.")
        /// Provider is disabled.
        internal static let errorProviderDisabled = ScreenshotL10n.tr("Localizable", "model.llm_provider.error_provider_disabled", fallback: "Provider is disabled.")
        /// Required fields missing: %@
        internal static func errorRequiredFieldsFormat(_ p1: Any) -> String {
          return ScreenshotL10n.tr("Localizable", "model.llm_provider.error_required_fields_format", String(describing: p1), fallback: "Required fields missing: %@")
        }
        /// API key
        internal static let fieldApiKey = ScreenshotL10n.tr("Localizable", "model.llm_provider.field_api_key", fallback: "API key")
        /// API key %@
        internal static func fieldApiKeyWithRequiredMarkFormat(_ p1: Any) -> String {
          return ScreenshotL10n.tr("Localizable", "model.llm_provider.field_api_key_with_required_mark_format", String(describing: p1), fallback: "API key %@")
        }
        /// Model
        internal static let fieldModel = ScreenshotL10n.tr("Localizable", "model.llm_provider.field_model", fallback: "Model")
        /// Enter a model name
        internal static let fieldModelPlaceholder = ScreenshotL10n.tr("Localizable", "model.llm_provider.field_model_placeholder", fallback: "Enter a model name")
        /// Name
        internal static let fieldName = ScreenshotL10n.tr("Localizable", "model.llm_provider.field_name", fallback: "Name")
        /// Provider name
        internal static let fieldNamePlaceholder = ScreenshotL10n.tr("Localizable", "model.llm_provider.field_name_placeholder", fallback: "Provider name")
        /// Service URL
        internal static let fieldServiceUrl = ScreenshotL10n.tr("Localizable", "model.llm_provider.field_service_url", fallback: "Service URL")
        /// API keys are stored in Keychain.
        internal static let keychainHint = ScreenshotL10n.tr("Localizable", "model.llm_provider.keychain_hint", fallback: "API keys are stored in Keychain.")
        /// Address
        internal static let labelAddress = ScreenshotL10n.tr("Localizable", "model.llm_provider.label_address", fallback: "Address")
        /// Model
        internal static let labelModel = ScreenshotL10n.tr("Localizable", "model.llm_provider.label_model", fallback: "Model")
        /// %@ (%d models)
        internal static func refreshModelsCountFormat(_ p1: Any, _ p2: Int) -> String {
          return ScreenshotL10n.tr("Localizable", "model.llm_provider.refresh_models_count_format", String(describing: p1), p2, fallback: "%@ (%d models)")
        }
        /// ,
        internal static let requiredFieldsSeparator = ScreenshotL10n.tr("Localizable", "model.llm_provider.required_fields_separator", fallback: ", ")
        /// Save
        internal static let save = ScreenshotL10n.tr("Localizable", "model.llm_provider.save", fallback: "Save")
        /// Add provider
        internal static let sheetTitleAdd = ScreenshotL10n.tr("Localizable", "model.llm_provider.sheet_title_add", fallback: "Add provider")
        /// Edit provider
        internal static let sheetTitleEdit = ScreenshotL10n.tr("Localizable", "model.llm_provider.sheet_title_edit", fallback: "Edit provider")
        /// Disabled
        internal static let statusDisabled = ScreenshotL10n.tr("Localizable", "model.llm_provider.status_disabled", fallback: "Disabled")
        /// Enabled
        internal static let statusEnabled = ScreenshotL10n.tr("Localizable", "model.llm_provider.status_enabled", fallback: "Enabled")
        /// Test
        internal static let test = ScreenshotL10n.tr("Localizable", "model.llm_provider.test", fallback: "Test")
        /// Test connection
        internal static let testConnection = ScreenshotL10n.tr("Localizable", "model.llm_provider.test_connection", fallback: "Test connection")
        /// LLM Providers
        internal static let title = ScreenshotL10n.tr("Localizable", "model.llm_provider.title", fallback: "LLM Providers")
        /// Enable provider
        internal static let toggleEnable = ScreenshotL10n.tr("Localizable", "model.llm_provider.toggle_enable", fallback: "Enable provider")
        /// API key
        internal static let validationFieldApiKey = ScreenshotL10n.tr("Localizable", "model.llm_provider.validation_field_api_key", fallback: "API key")
        /// Base URL
        internal static let validationFieldBaseUrl = ScreenshotL10n.tr("Localizable", "model.llm_provider.validation_field_base_url", fallback: "Base URL")
        /// Model
        internal static let validationFieldModel = ScreenshotL10n.tr("Localizable", "model.llm_provider.validation_field_model", fallback: "Model")
        /// Name
        internal static let validationFieldName = ScreenshotL10n.tr("Localizable", "model.llm_provider.validation_field_name", fallback: "Name")
      }
    }
    internal enum Navigation {
      internal enum Route {
        /// File Transcription
        internal static let fileTranscription = ScreenshotL10n.tr("Localizable", "navigation.route.file_transcription", fallback: "File Transcription")
        /// Help
        internal static let help = ScreenshotL10n.tr("Localizable", "navigation.route.help", fallback: "Help")
        /// Workbench and home dashboard
        internal static let home = ScreenshotL10n.tr("Localizable", "navigation.route.home", fallback: "Home")
        /// Notes
        internal static let notes = ScreenshotL10n.tr("Localizable", "navigation.route.notes", fallback: "Notes")
        /// Multimedia
        internal static let screenshotRecord = ScreenshotL10n.tr("Localizable", "navigation.route.screenshot_record", fallback: "Multimedia")
        /// Settings
        internal static let settings = ScreenshotL10n.tr("Localizable", "navigation.route.settings", fallback: "Settings")
        /// Styles
        internal static let styles = ScreenshotL10n.tr("Localizable", "navigation.route.styles", fallback: "Styles")
        /// AI Coding
        internal static let vibeCoding = ScreenshotL10n.tr("Localizable", "navigation.route.vibe_coding", fallback: "AI Coding")
        /// Vocabulary
        internal static let voiceCorrection = ScreenshotL10n.tr("Localizable", "navigation.route.voice_correction", fallback: "Vocabulary")
      }
    }
    internal enum Notes {
      internal enum Editor {
        /// ===== Notes =====
        internal static func characterCountFormat(_ p1: Int) -> String {
          return ScreenshotL10n.tr("Localizable", "notes.editor.character_count_format", p1, fallback: "Character count: %d")
        }
        /// Finish
        internal static let finishAction = ScreenshotL10n.tr("Localizable", "notes.editor.finish_action", fallback: "Finish")
      }
      internal enum Error {
        /// No recognized content to save.
        internal static let noContentToSave = ScreenshotL10n.tr("Localizable", "notes.error.no_content_to_save", fallback: "No recognized content to save.")
        /// Note not found.
        internal static let notFound = ScreenshotL10n.tr("Localizable", "notes.error.not_found", fallback: "Note not found.")
        /// Note output cancelled.
        internal static let outputCancelled = ScreenshotL10n.tr("Localizable", "notes.error.output_cancelled", fallback: "Note output cancelled.")
        /// Failed to output note.
        internal static let outputFailed = ScreenshotL10n.tr("Localizable", "notes.error.output_failed", fallback: "Failed to output note.")
        /// Text was copied but not inserted into note.
        internal static let outputNotWritten = ScreenshotL10n.tr("Localizable", "notes.error.output_not_written", fallback: "Text was copied but not inserted into note.")
        /// Source content not found.
        internal static let sourceNotFound = ScreenshotL10n.tr("Localizable", "notes.error.source_not_found", fallback: "Source content not found.")
      }
      internal enum Feedback {
        /// Created note.
        internal static let created = ScreenshotL10n.tr("Localizable", "notes.feedback.created", fallback: "Created note.")
        /// Created empty draft.
        internal static let createdEmptyDraft = ScreenshotL10n.tr("Localizable", "notes.feedback.created_empty_draft", fallback: "Created empty draft.")
        /// Deleted note.
        internal static let deleted = ScreenshotL10n.tr("Localizable", "notes.feedback.deleted", fallback: "Deleted note.")
        /// Generated Markdown export content.
        internal static let exportedMarkdown = ScreenshotL10n.tr("Localizable", "notes.feedback.exported_markdown", fallback: "Generated Markdown export content.")
        /// Saved recording to recent notes.
        internal static let recordingSavedRecently = ScreenshotL10n.tr("Localizable", "notes.feedback.recording_saved_recently", fallback: "Saved recording to recent notes.")
        /// Saved note.
        internal static let saved = ScreenshotL10n.tr("Localizable", "notes.feedback.saved", fallback: "Saved note.")
        /// Saved note from history.
        internal static let savedFromHistory = ScreenshotL10n.tr("Localizable", "notes.feedback.saved_from_history", fallback: "Saved note from history.")
        /// Saved note from transcription.
        internal static let savedFromTranscription = ScreenshotL10n.tr("Localizable", "notes.feedback.saved_from_transcription", fallback: "Saved note from transcription.")
      }
      internal enum NoteTitle {
        /// %@
        internal static func fromAppFormat(_ p1: Any) -> String {
          return ScreenshotL10n.tr("Localizable", "notes.note_title.from_app_format", String(describing: p1), fallback: "%@")
        }
        /// Dictation note
        internal static let recordingFallback = ScreenshotL10n.tr("Localizable", "notes.note_title.recording_fallback", fallback: "Dictation note")
        /// Untitled
        internal static let untitled = ScreenshotL10n.tr("Localizable", "notes.note_title.untitled", fallback: "Untitled")
      }
      internal enum Recording {
        /// Finish recording
        internal static let finishHelp = ScreenshotL10n.tr("Localizable", "notes.recording.finish_help", fallback: "Finish recording")
        /// Finalizing transcription...
        internal static let placeholderFinishing = ScreenshotL10n.tr("Localizable", "notes.recording.placeholder_finishing", fallback: "Finalizing transcription...")
        /// Speak, and I'll take notes for you...
        internal static let placeholderIdle = ScreenshotL10n.tr("Localizable", "notes.recording.placeholder_idle", fallback: "Speak, and I'll take notes for you...")
        /// Listening...
        internal static let placeholderRecording = ScreenshotL10n.tr("Localizable", "notes.recording.placeholder_recording", fallback: "Listening...")
        /// Start recording
        internal static let startHelp = ScreenshotL10n.tr("Localizable", "notes.recording.start_help", fallback: "Start recording")
      }
      internal enum View {
        /// Close preview
        internal static let closePreviewHelp = ScreenshotL10n.tr("Localizable", "notes.view.close_preview_help", fallback: "Close preview")
        /// Delete note
        internal static let deleteHelp = ScreenshotL10n.tr("Localizable", "notes.view.delete_help", fallback: "Delete note")
        /// No notes yet.
        internal static let emptyState = ScreenshotL10n.tr("Localizable", "notes.view.empty_state", fallback: "No notes yet.")
        /// Export Markdown
        internal static let exportMarkdownHelp = ScreenshotL10n.tr("Localizable", "notes.view.export_markdown_help", fallback: "Export Markdown")
        /// Quick Capture
        internal static let quickCaptureTitle = ScreenshotL10n.tr("Localizable", "notes.view.quick_capture_title", fallback: "Quick Capture")
        /// Recent Notes
        internal static let recentNotesTitle = ScreenshotL10n.tr("Localizable", "notes.view.recent_notes_title", fallback: "Recent Notes")
        /// Search notes
        internal static let searchHelp = ScreenshotL10n.tr("Localizable", "notes.view.search_help", fallback: "Search notes")
        /// Search notes
        internal static let searchPlaceholder = ScreenshotL10n.tr("Localizable", "notes.view.search_placeholder", fallback: "Search notes")
        /// Toggle grid/list view
        internal static let showAsGridHelp = ScreenshotL10n.tr("Localizable", "notes.view.show_as_grid_help", fallback: "Toggle grid/list view")
      }
    }
    internal enum NotesRecording {
      internal enum Error {
        /// Microphone access is missing. Please allow VoxFlow to use the microphone in System Settings.
        internal static let microphonePermissionDenied = ScreenshotL10n.tr("Localizable", "notes_recording.error.microphone_permission_denied", fallback: "Microphone access is missing. Please allow VoxFlow to use the microphone in System Settings.")
        /// Speech recognition access is missing. Please allow VoxFlow to use speech recognition in System Settings.
        internal static let speechPermissionDenied = ScreenshotL10n.tr("Localizable", "notes_recording.error.speech_permission_denied", fallback: "Speech recognition access is missing. Please allow VoxFlow to use speech recognition in System Settings.")
      }
    }
    internal enum Ocr {
      internal enum Context {
        /// OCR char count
        internal static let charCount = ScreenshotL10n.tr("Localizable", "ocr.context.char_count", fallback: "OCR char count")
        /// Context source
        internal static let contextSource = ScreenshotL10n.tr("Localizable", "ocr.context.context_source", fallback: "Context source")
        /// OCR temporary context
        internal static let sourceApp = ScreenshotL10n.tr("Localizable", "ocr.context.source_app", fallback: "Source app")
        /// Term count
        internal static let termCount = ScreenshotL10n.tr("Localizable", "ocr.context.term_count", fallback: "Term count")
        /// Validity
        internal static let validity = ScreenshotL10n.tr("Localizable", "ocr.context.validity", fallback: "Validity")
      }
    }
    internal enum Palette {
      internal enum Action {
        /// Actions
        internal static let menu = ScreenshotL10n.tr("Localizable", "palette.action.menu", fallback: "Actions")
      }
      internal enum Asset {
        /// Content Type
        internal static let infoContentTypeLabel = ScreenshotL10n.tr("Localizable", "palette.asset.info_content_type_label", fallback: "Content Type")
        /// File Path
        internal static let infoFilePathLabel = ScreenshotL10n.tr("Localizable", "palette.asset.info_file_path_label", fallback: "File Path")
        /// Image Path
        internal static let infoImagePathLabel = ScreenshotL10n.tr("Localizable", "palette.asset.info_image_path_label", fallback: "Image Path")
        /// Source
        internal static let infoSourceLabel = ScreenshotL10n.tr("Localizable", "palette.asset.info_source_label", fallback: "Source")
        /// Details
        internal static let infoTitle = ScreenshotL10n.tr("Localizable", "palette.asset.info_title", fallback: "Details")
        internal enum Source {
          /// Clipboard
          internal static let clipboard = ScreenshotL10n.tr("Localizable", "palette.asset.source.clipboard", fallback: "Clipboard")
          /// Dictation
          internal static let dictation = ScreenshotL10n.tr("Localizable", "palette.asset.source.dictation", fallback: "Dictation")
          /// Screenshot
          internal static let screenshot = ScreenshotL10n.tr("Localizable", "palette.asset.source.screenshot", fallback: "Screenshot")
        }
      }
      internal enum Assets {
        /// No assets yet
        internal static let empty = ScreenshotL10n.tr("Localizable", "palette.assets.empty", fallback: "No assets yet")
        /// Suggestions and available features are still shown.
        internal static let emptyPinnedSubtitle = ScreenshotL10n.tr("Localizable", "palette.assets.empty_pinned_subtitle", fallback: "Suggestions and available features are still shown.")
        /// No pinned items
        internal static let emptyPinnedTitle = ScreenshotL10n.tr("Localizable", "palette.assets.empty_pinned_title", fallback: "No pinned items")
      }
      internal enum ContentType {
        /// Color
        internal static let color = ScreenshotL10n.tr("Localizable", "palette.content_type.color", fallback: "Color")
        /// File
        internal static let file = ScreenshotL10n.tr("Localizable", "palette.content_type.file", fallback: "File")
        /// Image
        internal static let image = ScreenshotL10n.tr("Localizable", "palette.content_type.image", fallback: "Image")
        /// Link
        internal static let link = ScreenshotL10n.tr("Localizable", "palette.content_type.link", fallback: "Link")
        /// Text
        internal static let text = ScreenshotL10n.tr("Localizable", "palette.content_type.text", fallback: "Text")
      }
      internal enum Filter {
        /// All types
        internal static let all = ScreenshotL10n.tr("Localizable", "palette.filter.all", fallback: "All types")
      }
      internal enum ItemKind {
        /// App
        internal static let application = ScreenshotL10n.tr("Localizable", "palette.item_kind.application", fallback: "App")
        /// Command
        internal static let command = ScreenshotL10n.tr("Localizable", "palette.item_kind.command", fallback: "Command")
        /// Link
        internal static let link = ScreenshotL10n.tr("Localizable", "palette.item_kind.link", fallback: "Link")
        /// Search
        internal static let quicklink = ScreenshotL10n.tr("Localizable", "palette.item_kind.quicklink", fallback: "Search")
      }
      internal enum RootItem {
        internal enum Action {
          /// Add Favorite
          internal static let addFavorite = ScreenshotL10n.tr("Localizable", "palette.root_item.action.add_favorite", fallback: "Add Favorite")
          /// Open
          internal static let `open` = ScreenshotL10n.tr("Localizable", "palette.root_item.action.open", fallback: "Open")
          /// Open Link
          internal static let openLink = ScreenshotL10n.tr("Localizable", "palette.root_item.action.open_link", fallback: "Open Link")
          /// Paste
          internal static let paste = ScreenshotL10n.tr("Localizable", "palette.root_item.action.paste", fallback: "Paste")
          /// Paste File Path
          internal static let pasteFilePath = ScreenshotL10n.tr("Localizable", "palette.root_item.action.paste_file_path", fallback: "Paste File Path")
          /// Remove Favorite
          internal static let removeFavorite = ScreenshotL10n.tr("Localizable", "palette.root_item.action.remove_favorite", fallback: "Remove Favorite")
        }
        internal enum AskAi {
          /// Ask directly with a configured model
          internal static let subtitleEmpty = ScreenshotL10n.tr("Localizable", "palette.root_item.ask_ai.subtitle_empty", fallback: "Ask directly with a configured model")
          /// Ask %@
          internal static func subtitleWithQuery(_ p1: Any) -> String {
            return ScreenshotL10n.tr("Localizable", "palette.root_item.ask_ai.subtitle_with_query", String(describing: p1), fallback: "Ask %@")
          }
        }
        internal enum Quicklink {
          /// Search %@
          internal static func searchSubtitleFormat(_ p1: Any) -> String {
            return ScreenshotL10n.tr("Localizable", "palette.root_item.quicklink.search_subtitle_format", String(describing: p1), fallback: "Search %@")
          }
          /// %@ Search
          internal static func searchTitleFormat(_ p1: Any) -> String {
            return ScreenshotL10n.tr("Localizable", "palette.root_item.quicklink.search_title_format", String(describing: p1), fallback: "%@ Search")
          }
        }
        internal enum Subtitle {
          /// Dictate your request to produce directly inputtable text
          internal static let agentCompose = ScreenshotL10n.tr("Localizable", "palette.root_item.subtitle.agent_compose", fallback: "Dictate your request to produce directly inputtable text")
          /// Activate AI coding control console
          internal static let agentDispatch = ScreenshotL10n.tr("Localizable", "palette.root_item.subtitle.agent_dispatch", fallback: "Activate AI coding control console")
          /// Application
          internal static let application = ScreenshotL10n.tr("Localizable", "palette.root_item.subtitle.application", fallback: "Application")
          /// View all asset history
          internal static let assetHistory = ScreenshotL10n.tr("Localizable", "palette.root_item.subtitle.asset_history", fallback: "View all asset history")
          /// Open recent voice, screenshot, and clipboard assets
          internal static let recentAssets = ScreenshotL10n.tr("Localizable", "palette.root_item.subtitle.recent_assets", fallback: "Open recent voice, screenshot, and clipboard assets")
          /// Select and OCR an area
          internal static let screenshotOcr = ScreenshotL10n.tr("Localizable", "palette.root_item.subtitle.screenshot_ocr", fallback: "Select and OCR an area")
          /// Hold shortcut and dictate
          internal static let startDictation = ScreenshotL10n.tr("Localizable", "palette.root_item.subtitle.start_dictation", fallback: "Hold shortcut and dictate")
        }
        internal enum Title {
          /// Speak for Me
          internal static let agentCompose = ScreenshotL10n.tr("Localizable", "palette.root_item.title.agent_compose", fallback: "Speak for Me")
          /// AI Coding
          internal static let agentDispatch = ScreenshotL10n.tr("Localizable", "palette.root_item.title.agent_dispatch", fallback: "AI Coding")
          /// Ask AI
          internal static let askAi = ScreenshotL10n.tr("Localizable", "palette.root_item.title.ask_ai", fallback: "Ask AI")
          /// Asset History
          internal static let assetHistory = ScreenshotL10n.tr("Localizable", "palette.root_item.title.asset_history", fallback: "Asset History")
          /// Open URL
          internal static let openWebsite = ScreenshotL10n.tr("Localizable", "palette.root_item.title.open_website", fallback: "Open URL")
          /// Recent Assets
          internal static let recentAssets = ScreenshotL10n.tr("Localizable", "palette.root_item.title.recent_assets", fallback: "Recent Assets")
          /// Screenshot OCR
          internal static let screenshotOcr = ScreenshotL10n.tr("Localizable", "palette.root_item.title.screenshot_ocr", fallback: "Screenshot OCR")
          /// Start Dictation
          internal static let startDictation = ScreenshotL10n.tr("Localizable", "palette.root_item.title.start_dictation", fallback: "Start Dictation")
          /// Translate
          internal static let translate = ScreenshotL10n.tr("Localizable", "palette.root_item.title.translate", fallback: "Translate")
        }
        internal enum Translate {
          /// Translate current input
          internal static let subtitleEmpty = ScreenshotL10n.tr("Localizable", "palette.root_item.translate.subtitle_empty", fallback: "Translate current input")
          /// Translate %@
          internal static func subtitleWithQuery(_ p1: Any) -> String {
            return ScreenshotL10n.tr("Localizable", "palette.root_item.translate.subtitle_with_query", String(describing: p1), fallback: "Translate %@")
          }
        }
      }
      internal enum Search {
        /// Search assets...
        internal static let assetsPlaceholder = ScreenshotL10n.tr("Localizable", "palette.search.assets_placeholder", fallback: "Search assets...")
        /// Search...
        internal static let filterPlaceholder = ScreenshotL10n.tr("Localizable", "palette.search.filter_placeholder", fallback: "Search...")
        /// ===== Palette =====
        internal static let homePlaceholder = ScreenshotL10n.tr("Localizable", "palette.search.home_placeholder", fallback: "Search apps, commands, and assets...")
      }
      internal enum Section {
        /// Favorites
        internal static let favorites = ScreenshotL10n.tr("Localizable", "palette.section.favorites", fallback: "Favorites")
        /// Results
        internal static let results = ScreenshotL10n.tr("Localizable", "palette.section.results", fallback: "Results")
        /// Suggestions
        internal static let suggestions = ScreenshotL10n.tr("Localizable", "palette.section.suggestions", fallback: "Suggestions")
        /// Today
        internal static let today = ScreenshotL10n.tr("Localizable", "palette.section.today", fallback: "Today")
      }
    }
    internal enum Permission {
      internal enum Alert {
        internal enum Body {
          /// ===== Permission copy =====
          internal static let aliyunEngine = ScreenshotL10n.tr("Localizable", "permission.alert.body.aliyun_engine", fallback: "Please grant microphone and screen permissions in System Settings > Privacy & Security, then return and allow access again.")
          /// Please grant microphone and speech recognition permissions in System Settings > Privacy & Security, then continue.
          internal static let apple = ScreenshotL10n.tr("Localizable", "permission.alert.body.apple", fallback: "Please grant microphone and speech recognition permissions in System Settings > Privacy & Security, then continue.")
          /// Please grant microphone permission in System Settings > Privacy & Security, then return and allow access to continue.
          internal static let microphoneOnlyCloud = ScreenshotL10n.tr("Localizable", "permission.alert.body.microphone_only_cloud", fallback: "Please grant microphone permission in System Settings > Privacy & Security, then return and allow access to continue.")
          /// Please grant microphone permission in System Settings > Privacy & Security, then return and allow access.
          internal static let microphoneOnlyLocal = ScreenshotL10n.tr("Localizable", "permission.alert.body.microphone_only_local", fallback: "Please grant microphone permission in System Settings > Privacy & Security, then return and allow access.")
        }
        internal enum Title {
          /// Enable microphone and speech permissions
          internal static let audioAndSpeech = ScreenshotL10n.tr("Localizable", "permission.alert.title.audio_and_speech", fallback: "Enable microphone and speech permissions")
          /// Enable microphone permission
          internal static let microphoneOnly = ScreenshotL10n.tr("Localizable", "permission.alert.title.microphone_only", fallback: "Enable microphone permission")
          /// Enable screen recording permission
          internal static let screenRecording = ScreenshotL10n.tr("Localizable", "permission.alert.title.screen_recording", fallback: "Enable screen recording permission")
        }
      }
      internal enum Guide {
        /// ===== Permission guide =====
        internal static let returnToAppCheck = ScreenshotL10n.tr("Localizable", "permission.guide.return_to_app_check", fallback: "After changing permissions, please return to VoxFlow and recheck.")
      }
      internal enum Item {
        /// Required to capture shortcuts and shortcut state.
        internal static let accessibilitySubtitle = ScreenshotL10n.tr("Localizable", "permission.item.accessibility_subtitle", fallback: "Required to capture shortcuts and shortcut state.")
        /// Accessibility
        internal static let accessibilityTitle = ScreenshotL10n.tr("Localizable", "permission.item.accessibility_title", fallback: "Accessibility")
        /// Required to record your voice.
        internal static let microphoneSubtitle = ScreenshotL10n.tr("Localizable", "permission.item.microphone_subtitle", fallback: "Required to record your voice.")
        /// Microphone
        internal static let microphoneTitle = ScreenshotL10n.tr("Localizable", "permission.item.microphone_title", fallback: "Microphone")
        /// Required to capture selected screen content.
        internal static let screenRecordingSubtitle = ScreenshotL10n.tr("Localizable", "permission.item.screen_recording_subtitle", fallback: "Required to capture selected screen content.")
        /// Screen Recording
        internal static let screenRecordingTitle = ScreenshotL10n.tr("Localizable", "permission.item.screen_recording_title", fallback: "Screen Recording")
        /// Required for speech recognition.
        internal static let speechSubtitle = ScreenshotL10n.tr("Localizable", "permission.item.speech_subtitle", fallback: "Required for speech recognition.")
        /// Speech Recognition
        internal static let speechTitle = ScreenshotL10n.tr("Localizable", "permission.item.speech_title", fallback: "Speech Recognition")
      }
      internal enum Screen {
        internal enum Recording {
          /// VoxFlow requires Screen Recording permission to capture screen content, and then the permission can be enabled in “Privacy and Security > Screen Recording”.
          internal static let description = ScreenshotL10n.tr("Localizable", "permission.screen.recording.description", fallback: "VoxFlow requires Screen Recording permission to capture screen content, and then the permission can be enabled in “Privacy and Security > Screen Recording”.")
        }
      }
      internal enum Settings {
        /// System Settings > Privacy & Security
        internal static let security = ScreenshotL10n.tr("Localizable", "permission.settings.security", fallback: "System Settings > Privacy & Security")
        /// Privacy and Security > Screen Recording
        internal static let securityPath = ScreenshotL10n.tr("Localizable", "permission.settings.security_path", fallback: "Privacy and Security > Screen Recording")
      }
      internal enum Status {
        /// Denied
        internal static let denied = ScreenshotL10n.tr("Localizable", "permission.status.denied", fallback: "Denied")
        /// Enabled
        internal static let granted = ScreenshotL10n.tr("Localizable", "permission.status.granted", fallback: "Enabled")
      }
    }
    internal enum Product {
      internal enum Brand {
        /// 码上写
        internal static let chineseDisplayName = ScreenshotL10n.tr("Localizable", "product.brand.chinese_display_name", fallback: "码上写")
        /// ===== Product brand =====
        internal static let englishName = ScreenshotL10n.tr("Localizable", "product.brand.english_name", fallback: "VoxFlow")
      }
    }
    internal enum Provider {
      internal enum Tag {
        /// Provider hotword tag
        internal static let hotwords = ScreenshotL10n.tr("Localizable", "provider.tag.hotwords", fallback: "Smart Correction")
      }
    }
    internal enum Recording {
      internal enum Error {
        /// Display not found.
        internal static let displayNotFound = ScreenshotL10n.tr("Localizable", "recording.error.display_not_found", fallback: "Display not found.")
        /// Failed to delete recording file: %@
        internal static func fileDeleteFailedFormat(_ p1: Any) -> String {
          return ScreenshotL10n.tr("Localizable", "recording.error.file_delete_failed_format", String(describing: p1), fallback: "Failed to delete recording file: %@")
        }
        /// Failed to finalize recording file: %@
        internal static func fileFinalizeFailedFormat(_ p1: Any) -> String {
          return ScreenshotL10n.tr("Localizable", "recording.error.file_finalize_failed_format", String(describing: p1), fallback: "Failed to finalize recording file: %@")
        }
        /// Failed to finish recording: %@
        internal static func finalizeFailedFormat(_ p1: Any) -> String {
          return ScreenshotL10n.tr("Localizable", "recording.error.finalize_failed_format", String(describing: p1), fallback: "Failed to finish recording: %@")
        }
        /// Could not add microphone input.
        internal static let microphoneInputAddFailed = ScreenshotL10n.tr("Localizable", "recording.error.microphone_input_add_failed", fallback: "Could not add microphone input.")
        /// Microphone permission is denied.
        internal static let microphonePermissionDenied = ScreenshotL10n.tr("Localizable", "recording.error.microphone_permission_denied", fallback: "Microphone permission is denied.")
        /// Recording is not running.
        internal static let notRunning = ScreenshotL10n.tr("Localizable", "recording.error.not_running", fallback: "Recording is not running.")
        /// Failed to start recording stream: %@
        internal static func streamStartFailedFormat(_ p1: Any) -> String {
          return ScreenshotL10n.tr("Localizable", "recording.error.stream_start_failed_format", String(describing: p1), fallback: "Failed to start recording stream: %@")
        }
        /// Temporary recording file is missing: %@
        internal static func temporaryFileMissingFormat(_ p1: Any) -> String {
          return ScreenshotL10n.tr("Localizable", "recording.error.temporary_file_missing_format", String(describing: p1), fallback: "Temporary recording file is missing: %@")
        }
        /// Could not add video input.
        internal static let videoInputAddFailed = ScreenshotL10n.tr("Localizable", "recording.error.video_input_add_failed", fallback: "Could not add video input.")
        /// Failed to prepare recording writer: %@
        internal static func writerSetupFailedFormat(_ p1: Any) -> String {
          return ScreenshotL10n.tr("Localizable", "recording.error.writer_setup_failed_format", String(describing: p1), fallback: "Failed to prepare recording writer: %@")
        }
        /// Failed to start recording writer: %@
        internal static func writerStartFailedFormat(_ p1: Any) -> String {
          return ScreenshotL10n.tr("Localizable", "recording.error.writer_start_failed_format", String(describing: p1), fallback: "Failed to start recording writer: %@")
        }
      }
      internal enum Feedback {
        /// Recording deleted
        internal static let deleteConfirmation = ScreenshotL10n.tr("Localizable", "recording.feedback.delete_confirmation", fallback: "Recording deleted")
        /// Failed to delete recording
        internal static let deleteFailed = ScreenshotL10n.tr("Localizable", "recording.feedback.delete_failed", fallback: "Failed to delete recording")
        /// File copied
        internal static let fileCopied = ScreenshotL10n.tr("Localizable", "recording.feedback.file_copied", fallback: "File copied")
        /// File not found
        internal static let fileNotFound = ScreenshotL10n.tr("Localizable", "recording.feedback.file_not_found", fallback: "File not found")
        /// File saved
        internal static let fileSaved = ScreenshotL10n.tr("Localizable", "recording.feedback.file_saved", fallback: "File saved")
        /// File opened
        internal static let openedFile = ScreenshotL10n.tr("Localizable", "recording.feedback.opened_file", fallback: "File opened")
        /// Recording deleted
        internal static let recordingDeleted = ScreenshotL10n.tr("Localizable", "recording.feedback.recording_deleted", fallback: "Recording deleted")
        /// Shown in Finder
        internal static let revealedInFinder = ScreenshotL10n.tr("Localizable", "recording.feedback.revealed_in_finder", fallback: "Shown in Finder")
        /// Save cancelled
        internal static let saveCancelled = ScreenshotL10n.tr("Localizable", "recording.feedback.save_cancelled", fallback: "Save cancelled")
      }
      internal enum Hud {
        /// Copy
        internal static let actionCopy = ScreenshotL10n.tr("Localizable", "recording.hud.action_copy", fallback: "Copy")
        /// Copied
        internal static let actionCopyDone = ScreenshotL10n.tr("Localizable", "recording.hud.action_copy_done", fallback: "Copied")
        /// Copy the recording file
        internal static let actionCopyHelp = ScreenshotL10n.tr("Localizable", "recording.hud.action_copy_help", fallback: "Copy the recording file")
        /// Delete
        internal static let actionDelete = ScreenshotL10n.tr("Localizable", "recording.hud.action_delete", fallback: "Delete")
        /// Delete again to confirm
        internal static let actionDeleteConfirm = ScreenshotL10n.tr("Localizable", "recording.hud.action_delete_confirm", fallback: "Delete again to confirm")
        /// Delete this recording permanently
        internal static let actionDeleteConfirmHelp = ScreenshotL10n.tr("Localizable", "recording.hud.action_delete_confirm_help", fallback: "Delete this recording permanently")
        /// Delete this recording
        internal static let actionDeleteHelp = ScreenshotL10n.tr("Localizable", "recording.hud.action_delete_help", fallback: "Delete this recording")
        /// Save As
        internal static let actionDownload = ScreenshotL10n.tr("Localizable", "recording.hud.action_download", fallback: "Save As")
        /// Saved
        internal static let actionDownloadDone = ScreenshotL10n.tr("Localizable", "recording.hud.action_download_done", fallback: "Saved")
        /// Save a copy of the recording
        internal static let actionDownloadHelp = ScreenshotL10n.tr("Localizable", "recording.hud.action_download_help", fallback: "Save a copy of the recording")
        /// Open
        internal static let actionOpen = ScreenshotL10n.tr("Localizable", "recording.hud.action_open", fallback: "Open")
        /// Open the recording file
        internal static let actionOpenHelp = ScreenshotL10n.tr("Localizable", "recording.hud.action_open_help", fallback: "Open the recording file")
        /// Show the recording in Finder
        internal static let actionRevealInFinderHelp = ScreenshotL10n.tr("Localizable", "recording.hud.action_reveal_in_finder_help", fallback: "Show the recording in Finder")
      }
      internal enum Result {
        /// Close
        internal static let actionClose = ScreenshotL10n.tr("Localizable", "recording.result.action_close", fallback: "Close")
        /// Recording saved
        internal static let titleSaved = ScreenshotL10n.tr("Localizable", "recording.result.title_saved", fallback: "Recording saved")
      }
    }
    internal enum Screenshot {
      internal enum Capture {
        internal enum Error {
          /// Screenshot cancelled.
          internal static let cancelled = ScreenshotL10n.tr("Localizable", "screenshot.capture.error.cancelled", fallback: "Screenshot cancelled.")
          /// Could not decode the captured screenshot.
          internal static let decodeFailure = ScreenshotL10n.tr("Localizable", "screenshot.capture.error.decode_failure", fallback: "Could not decode the captured screenshot.")
          /// Could not read the captured screenshot.
          internal static let readingFailure = ScreenshotL10n.tr("Localizable", "screenshot.capture.error.reading_failure", fallback: "Could not read the captured screenshot.")
          /// Could not start screenshot capture.
          internal static let startFailure = ScreenshotL10n.tr("Localizable", "screenshot.capture.error.start_failure", fallback: "Could not start screenshot capture.")
        }
      }
      internal enum ImageStorage {
        internal enum Error {
          /// Could not create an image bitmap.
          internal static let bitmapRepFailed = ScreenshotL10n.tr("Localizable", "screenshot.image_storage.error.bitmap_rep_failed", fallback: "Could not create an image bitmap.")
          /// Could not encode the image as PNG.
          internal static let pngEncodeFailed = ScreenshotL10n.tr("Localizable", "screenshot.image_storage.error.png_encode_failed", fallback: "Could not encode the image as PNG.")
        }
      }
      internal enum Ocr {
        /// No text recognized in the screenshot.
        internal static let noTextForScreenshot = ScreenshotL10n.tr("Localizable", "screenshot.ocr.no_text_for_screenshot", fallback: "No text recognized in the screenshot.")
      }
      internal enum Panel {
        /// Screenshot
        internal static let title = ScreenshotL10n.tr("Localizable", "screenshot.panel.title", fallback: "Screenshot")
        /// Recognition Complete
        internal static let titleRecognitionComplete = ScreenshotL10n.tr("Localizable", "screenshot.panel.title_recognition_complete", fallback: "Recognition Complete")
        /// Scrolling Capture Complete
        internal static let titleScrollingCapture = ScreenshotL10n.tr("Localizable", "screenshot.panel.title_scrolling_capture", fallback: "Scrolling Capture Complete")
        internal enum Action {
          /// Copy Image
          internal static let copyImage = ScreenshotL10n.tr("Localizable", "screenshot.panel.action.copy_image", fallback: "Copy Image")
          /// Copy Text
          internal static let copyText = ScreenshotL10n.tr("Localizable", "screenshot.panel.action.copy_text", fallback: "Copy Text")
          /// Speak
          internal static let speak = ScreenshotL10n.tr("Localizable", "screenshot.panel.action.speak", fallback: "Speak")
          /// Translate
          internal static let translate = ScreenshotL10n.tr("Localizable", "screenshot.panel.action.translate", fallback: "Translate")
        }
        internal enum Placeholder {
          /// No screenshot
          internal static let noScreenshot = ScreenshotL10n.tr("Localizable", "screenshot.panel.placeholder.no_screenshot", fallback: "No screenshot")
          /// No translation overlay
          internal static let noTranslationOverlay = ScreenshotL10n.tr("Localizable", "screenshot.panel.placeholder.no_translation_overlay", fallback: "No translation overlay")
        }
        internal enum Tab {
          /// OCR
          internal static let ocr = ScreenshotL10n.tr("Localizable", "screenshot.panel.tab.ocr", fallback: "OCR")
          /// Original
          internal static let originalImage = ScreenshotL10n.tr("Localizable", "screenshot.panel.tab.original_image", fallback: "Original")
          /// Summary
          internal static let summary = ScreenshotL10n.tr("Localizable", "screenshot.panel.tab.summary", fallback: "Summary")
          /// Translation
          internal static let translation = ScreenshotL10n.tr("Localizable", "screenshot.panel.tab.translation", fallback: "Translation")
        }
      }
      internal enum Record {
        /// %d chars
        internal static func charCountFormat(_ p1: Int) -> String {
          return ScreenshotL10n.tr("Localizable", "screenshot.record.char_count_format", p1, fallback: "%d chars")
        }
        /// Captured screenshots and recordings will appear here.
        internal static let emptyHint = ScreenshotL10n.tr("Localizable", "screenshot.record.empty_hint", fallback: "Captured screenshots and recordings will appear here.")
        /// No media records yet
        internal static let emptyTitle = ScreenshotL10n.tr("Localizable", "screenshot.record.empty_title", fallback: "No media records yet")
        /// Filter
        internal static let filterLabel = ScreenshotL10n.tr("Localizable", "screenshot.record.filter_label", fallback: "Filter")
        /// Media
        internal static let headerTitle = ScreenshotL10n.tr("Localizable", "screenshot.record.header_title", fallback: "Media")
        /// No text
        internal static let noText = ScreenshotL10n.tr("Localizable", "screenshot.record.no_text", fallback: "No text")
        /// Next
        internal static let pageNext = ScreenshotL10n.tr("Localizable", "screenshot.record.page_next", fallback: "Next")
        /// Previous
        internal static let pagePrev = ScreenshotL10n.tr("Localizable", "screenshot.record.page_prev", fallback: "Previous")
        /// %d per page
        internal static func pageSizeFormat(_ p1: Int) -> String {
          return ScreenshotL10n.tr("Localizable", "screenshot.record.page_size_format", p1, fallback: "%d per page")
        }
        /// Page size
        internal static let pageSizeLabel = ScreenshotL10n.tr("Localizable", "screenshot.record.page_size_label", fallback: "Page size")
        /// Search media
        internal static let searchPlaceholder = ScreenshotL10n.tr("Localizable", "screenshot.record.search_placeholder", fallback: "Search media")
        /// %d items
        internal static func totalCountFormat(_ p1: Int) -> String {
          return ScreenshotL10n.tr("Localizable", "screenshot.record.total_count_format", p1, fallback: "%d items")
        }
        internal enum Action {
          /// Copy file
          internal static let copyFileHelp = ScreenshotL10n.tr("Localizable", "screenshot.record.action.copy_file_help", fallback: "Copy file")
          /// Copy image
          internal static let copyImageHelp = ScreenshotL10n.tr("Localizable", "screenshot.record.action.copy_image_help", fallback: "Copy image")
          /// Copy text
          internal static let copyTextHelp = ScreenshotL10n.tr("Localizable", "screenshot.record.action.copy_text_help", fallback: "Copy text")
          /// Delete record
          internal static let deleteHelp = ScreenshotL10n.tr("Localizable", "screenshot.record.action.delete_help", fallback: "Delete record")
          /// Add to favorites
          internal static let favoriteHelp = ScreenshotL10n.tr("Localizable", "screenshot.record.action.favorite_help", fallback: "Add to favorites")
          /// Open file
          internal static let openFileHelp = ScreenshotL10n.tr("Localizable", "screenshot.record.action.open_file_help", fallback: "Open file")
          /// Show in Finder
          internal static let revealInFinderHelp = ScreenshotL10n.tr("Localizable", "screenshot.record.action.reveal_in_finder_help", fallback: "Show in Finder")
          /// Remove from favorites
          internal static let unfavoriteHelp = ScreenshotL10n.tr("Localizable", "screenshot.record.action.unfavorite_help", fallback: "Remove from favorites")
        }
        internal enum Audio {
          /// Microphone audio
          internal static let microphone = ScreenshotL10n.tr("Localizable", "screenshot.record.audio.microphone", fallback: "Microphone audio")
          /// No audio
          internal static let noSound = ScreenshotL10n.tr("Localizable", "screenshot.record.audio.no_sound", fallback: "No audio")
        }
        internal enum Detail {
          /// Close details
          internal static let actionCloseHelp = ScreenshotL10n.tr("Localizable", "screenshot.record.detail.action_close_help", fallback: "Close details")
          /// Burn subtitles
          internal static let burnConfirmAction = ScreenshotL10n.tr("Localizable", "screenshot.record.detail.burn_confirm_action", fallback: "Burn subtitles")
          /// Cancel
          internal static let burnConfirmCancel = ScreenshotL10n.tr("Localizable", "screenshot.record.detail.burn_confirm_cancel", fallback: "Cancel")
          /// This will create a new video with subtitles burned in.
          internal static let burnConfirmMessage = ScreenshotL10n.tr("Localizable", "screenshot.record.detail.burn_confirm_message", fallback: "This will create a new video with subtitles burned in.")
          /// Burn subtitles?
          internal static let burnConfirmTitle = ScreenshotL10n.tr("Localizable", "screenshot.record.detail.burn_confirm_title", fallback: "Burn subtitles?")
          /// Screen Recording
          internal static let headerScreenRecording = ScreenshotL10n.tr("Localizable", "screenshot.record.detail.header_screen_recording", fallback: "Screen Recording")
          /// Screenshot
          internal static let headerScreenshot = ScreenshotL10n.tr("Localizable", "screenshot.record.detail.header_screenshot", fallback: "Screenshot")
          /// Image unavailable
          internal static let mediaUnavailableImage = ScreenshotL10n.tr("Localizable", "screenshot.record.detail.media_unavailable_image", fallback: "Image unavailable")
          /// Video unavailable
          internal static let mediaUnavailableVideo = ScreenshotL10n.tr("Localizable", "screenshot.record.detail.media_unavailable_video", fallback: "Video unavailable")
          /// Audio
          internal static let metaLabelAudio = ScreenshotL10n.tr("Localizable", "screenshot.record.detail.meta_label_audio", fallback: "Audio")
          /// Characters
          internal static let metaLabelCharCount = ScreenshotL10n.tr("Localizable", "screenshot.record.detail.meta_label_char_count", fallback: "Characters")
          /// Duration
          internal static let metaLabelDuration = ScreenshotL10n.tr("Localizable", "screenshot.record.detail.meta_label_duration", fallback: "Duration")
          /// Favorite
          internal static let metaLabelFavorite = ScreenshotL10n.tr("Localizable", "screenshot.record.detail.meta_label_favorite", fallback: "Favorite")
          /// File size
          internal static let metaLabelFileSize = ScreenshotL10n.tr("Localizable", "screenshot.record.detail.meta_label_file_size", fallback: "File size")
          /// Resolution
          internal static let metaLabelResolution = ScreenshotL10n.tr("Localizable", "screenshot.record.detail.meta_label_resolution", fallback: "Resolution")
          /// Time
          internal static let metaLabelTime = ScreenshotL10n.tr("Localizable", "screenshot.record.detail.meta_label_time", fallback: "Time")
          /// Details
          internal static let metaTitle = ScreenshotL10n.tr("Localizable", "screenshot.record.detail.meta_title", fallback: "Details")
          /// Favorited
          internal static let metaValueFavorited = ScreenshotL10n.tr("Localizable", "screenshot.record.detail.meta_value_favorited", fallback: "Favorited")
          /// Not favorited
          internal static let metaValueUnfavorited = ScreenshotL10n.tr("Localizable", "screenshot.record.detail.meta_value_unfavorited", fallback: "Not favorited")
          /// No OCR text
          internal static let ocrNoText = ScreenshotL10n.tr("Localizable", "screenshot.record.detail.ocr_no_text", fallback: "No OCR text")
          /// OCR Text
          internal static let ocrTitle = ScreenshotL10n.tr("Localizable", "screenshot.record.detail.ocr_title", fallback: "OCR Text")
          /// Details
          internal static let statusLabel = ScreenshotL10n.tr("Localizable", "screenshot.record.detail.status_label", fallback: "Details")
          /// Add subtitles
          internal static let subtitleActionAdd = ScreenshotL10n.tr("Localizable", "screenshot.record.detail.subtitle_action_add", fallback: "Add subtitles")
          /// Generate subtitles for this recording
          internal static let subtitleActionAddHelp = ScreenshotL10n.tr("Localizable", "screenshot.record.detail.subtitle_action_add_help", fallback: "Generate subtitles for this recording")
          /// This recording has no microphone audio
          internal static let subtitleActionAddNoAudioHelp = ScreenshotL10n.tr("Localizable", "screenshot.record.detail.subtitle_action_add_no_audio_help", fallback: "This recording has no microphone audio")
          /// Burn subtitles
          internal static let subtitleActionBurn = ScreenshotL10n.tr("Localizable", "screenshot.record.detail.subtitle_action_burn", fallback: "Burn subtitles")
          /// Burn subtitles into the video
          internal static let subtitleActionBurnHelp = ScreenshotL10n.tr("Localizable", "screenshot.record.detail.subtitle_action_burn_help", fallback: "Burn subtitles into the video")
          /// Burning subtitles
          internal static let subtitleActionBurning = ScreenshotL10n.tr("Localizable", "screenshot.record.detail.subtitle_action_burning", fallback: "Burning subtitles")
          /// Burning subtitles into the video
          internal static let subtitleActionBurningHelp = ScreenshotL10n.tr("Localizable", "screenshot.record.detail.subtitle_action_burning_help", fallback: "Burning subtitles into the video")
          /// Generating subtitles
          internal static let subtitleActionGenerating = ScreenshotL10n.tr("Localizable", "screenshot.record.detail.subtitle_action_generating", fallback: "Generating subtitles")
          /// Transcribing microphone audio
          internal static let subtitleActionGeneratingHelp = ScreenshotL10n.tr("Localizable", "screenshot.record.detail.subtitle_action_generating_help", fallback: "Transcribing microphone audio")
          /// Open original video
          internal static let subtitleActionOpenOriginalVideo = ScreenshotL10n.tr("Localizable", "screenshot.record.detail.subtitle_action_open_original_video", fallback: "Open original video")
          /// Open the original video
          internal static let subtitleActionOpenOriginalVideoHelp = ScreenshotL10n.tr("Localizable", "screenshot.record.detail.subtitle_action_open_original_video_help", fallback: "Open the original video")
          /// Open subtitled video
          internal static let subtitleActionOpenSubtitledVideo = ScreenshotL10n.tr("Localizable", "screenshot.record.detail.subtitle_action_open_subtitled_video", fallback: "Open subtitled video")
          /// Open the subtitled video
          internal static let subtitleActionOpenSubtitledVideoHelp = ScreenshotL10n.tr("Localizable", "screenshot.record.detail.subtitle_action_open_subtitled_video_help", fallback: "Open the subtitled video")
          /// Retry subtitles
          internal static let subtitleActionRetry = ScreenshotL10n.tr("Localizable", "screenshot.record.detail.subtitle_action_retry", fallback: "Retry subtitles")
          /// Regenerate subtitles
          internal static let subtitleActionRetryHelp = ScreenshotL10n.tr("Localizable", "screenshot.record.detail.subtitle_action_retry_help", fallback: "Regenerate subtitles")
          /// View and edit
          internal static let subtitleActionViewEdit = ScreenshotL10n.tr("Localizable", "screenshot.record.detail.subtitle_action_view_edit", fallback: "View and edit")
          /// View or edit subtitles
          internal static let subtitleActionViewEditHelp = ScreenshotL10n.tr("Localizable", "screenshot.record.detail.subtitle_action_view_edit_help", fallback: "View or edit subtitles")
          /// Subtitles
          internal static let subtitleSectionTitle = ScreenshotL10n.tr("Localizable", "screenshot.record.detail.subtitle_section_title", fallback: "Subtitles")
          /// No microphone audio
          internal static let subtitleStatusNoMicrophone = ScreenshotL10n.tr("Localizable", "screenshot.record.detail.subtitle_status_no_microphone", fallback: "No microphone audio")
          /// Translation
          internal static let translationTitle = ScreenshotL10n.tr("Localizable", "screenshot.record.detail.translation_title", fallback: "Translation")
        }
        internal enum Error {
          /// Failed to copy file.
          internal static let copyFileFailed = ScreenshotL10n.tr("Localizable", "screenshot.record.error.copy_file_failed", fallback: "Failed to copy file.")
          /// File not found
          internal static let fileNotFound = ScreenshotL10n.tr("Localizable", "screenshot.record.error.file_not_found", fallback: "File not found")
          /// No file is available.
          internal static let noAvailableFile = ScreenshotL10n.tr("Localizable", "screenshot.record.error.no_available_file", fallback: "No file is available.")
          /// No copyable image is available.
          internal static let noCopyableImage = ScreenshotL10n.tr("Localizable", "screenshot.record.error.no_copyable_image", fallback: "No copyable image is available.")
          /// No OCR text available.
          internal static let noOcrText = ScreenshotL10n.tr("Localizable", "screenshot.record.error.no_ocr_text", fallback: "No OCR text available.")
          /// Original video is unavailable.
          internal static let originalVideoUnavailable = ScreenshotL10n.tr("Localizable", "screenshot.record.error.original_video_unavailable", fallback: "Original video is unavailable.")
          /// Subtitles are not ready yet.
          internal static let subtitleNotReady = ScreenshotL10n.tr("Localizable", "screenshot.record.error.subtitle_not_ready", fallback: "Subtitles are not ready yet.")
          /// Subtitled video is unavailable.
          internal static let subtitledVideoUnavailable = ScreenshotL10n.tr("Localizable", "screenshot.record.error.subtitled_video_unavailable", fallback: "Subtitled video is unavailable.")
        }
        internal enum Feedback {
          /// Subtitle burn started
          internal static let burnStarted = ScreenshotL10n.tr("Localizable", "screenshot.record.feedback.burn_started", fallback: "Subtitle burn started")
          /// File copied
          internal static let copiedFile = ScreenshotL10n.tr("Localizable", "screenshot.record.feedback.copied_file", fallback: "File copied")
          /// Image copied
          internal static let copiedImage = ScreenshotL10n.tr("Localizable", "screenshot.record.feedback.copied_image", fallback: "Image copied")
          /// Copied to clipboard
          internal static let copiedToClipboard = ScreenshotL10n.tr("Localizable", "screenshot.record.feedback.copied_to_clipboard", fallback: "Copied to clipboard")
          /// Deleted
          internal static let deleted = ScreenshotL10n.tr("Localizable", "screenshot.record.feedback.deleted", fallback: "Deleted")
          /// File opened
          internal static let openedFile = ScreenshotL10n.tr("Localizable", "screenshot.record.feedback.opened_file", fallback: "File opened")
          /// Original video opened
          internal static let openedOriginalVideo = ScreenshotL10n.tr("Localizable", "screenshot.record.feedback.opened_original_video", fallback: "Original video opened")
          /// Subtitled video opened
          internal static let openedSubtitledVideo = ScreenshotL10n.tr("Localizable", "screenshot.record.feedback.opened_subtitled_video", fallback: "Subtitled video opened")
          /// Shown in Finder
          internal static let revealedInFinder = ScreenshotL10n.tr("Localizable", "screenshot.record.feedback.revealed_in_finder", fallback: "Shown in Finder")
        }
        internal enum Format {
          /// yyyy-MM-dd HH:mm
          internal static let datetime = ScreenshotL10n.tr("Localizable", "screenshot.record.format.datetime", fallback: "yyyy-MM-dd HH:mm")
          /// Unknown file size: %d
          internal static func unknownFileSize(_ p1: Int) -> String {
            return ScreenshotL10n.tr("Localizable", "screenshot.record.format.unknown_file_size", p1, fallback: "Unknown file size: %d")
          }
          /// Unknown resolution: %@
          internal static func unknownResolution(_ p1: Any) -> String {
            return ScreenshotL10n.tr("Localizable", "screenshot.record.format.unknown_resolution", String(describing: p1), fallback: "Unknown resolution: %@")
          }
        }
        internal enum Stats {
          /// Screen Recordings
          internal static let screenRecording = ScreenshotL10n.tr("Localizable", "screenshot.record.stats.screen_recording", fallback: "Screen Recordings")
          /// Screenshots
          internal static let screenshot = ScreenshotL10n.tr("Localizable", "screenshot.record.stats.screenshot", fallback: "Screenshots")
          /// Today
          internal static let todayMedia = ScreenshotL10n.tr("Localizable", "screenshot.record.stats.today_media", fallback: "Today")
          /// Total Media
          internal static let totalMedia = ScreenshotL10n.tr("Localizable", "screenshot.record.stats.total_media", fallback: "Total Media")
          /// items
          internal static let unitItems = ScreenshotL10n.tr("Localizable", "screenshot.record.stats.unit_items", fallback: "items")
          /// recordings
          internal static let unitRecordings = ScreenshotL10n.tr("Localizable", "screenshot.record.stats.unit_recordings", fallback: "recordings")
          /// screenshots
          internal static let unitScreenshots = ScreenshotL10n.tr("Localizable", "screenshot.record.stats.unit_screenshots", fallback: "screenshots")
        }
      }
      internal enum Refine {
        internal enum Error {
          /// Configure a model before summarizing
          internal static let summaryModelRequires = ScreenshotL10n.tr("Localizable", "screenshot.refine.error.summary_model_requires", fallback: "Configure a model before summarizing")
          /// The summary model returned webpage or code content. Retry or use another configured model.
          internal static let summaryOutputInvalidContent = ScreenshotL10n.tr("Localizable", "screenshot.refine.error.summary_output_invalid_content", fallback: "The summary model returned webpage or code content. Retry or use another configured model.")
        }
        internal enum Unavailable {
          /// refine unavailable configuration required
          internal static let configRequired = ScreenshotL10n.tr("Localizable", "screenshot.refine.unavailable.config_required", fallback: "refine unavailable configuration required")
          /// Apple system translation is unavailable. Make sure macOS 15 or later is installed.
          internal static let systemTranslationOsVersion = ScreenshotL10n.tr("Localizable", "screenshot.refine.unavailable.system_translation_os_version", fallback: "Apple system translation is unavailable. Make sure macOS 15 or later is installed.")
        }
      }
      internal enum Result {
        /// Copied
        internal static let copied = ScreenshotL10n.tr("Localizable", "screenshot.result.copied", fallback: "Copied")
        /// Image copied
        internal static let copiedImage = ScreenshotL10n.tr("Localizable", "screenshot.result.copied_image", fallback: "Image copied")
        /// Failed to copy result.
        internal static let copyFailed = ScreenshotL10n.tr("Localizable", "screenshot.result.copy_failed", fallback: "Failed to copy result.")
        /// Failed to copy image.
        internal static let copyImageFailed = ScreenshotL10n.tr("Localizable", "screenshot.result.copy_image_failed", fallback: "Failed to copy image.")
        /// No copyable image
        internal static let noCopyableImage = ScreenshotL10n.tr("Localizable", "screenshot.result.no_copyable_image", fallback: "No copyable image")
        /// No recognized text to translate
        internal static let noTextForTranslation = ScreenshotL10n.tr("Localizable", "screenshot.result.no_text_for_translation", fallback: "No recognized text to translate")
        /// result original In clipboard
        internal static let originalInClipboard = ScreenshotL10n.tr("Localizable", "screenshot.result.original_in_clipboard", fallback: "result original In clipboard")
        /// Reading complete
        internal static let readComplete = ScreenshotL10n.tr("Localizable", "screenshot.result.read_complete", fallback: "Reading complete")
        /// result read No content
        internal static let readNoContent = ScreenshotL10n.tr("Localizable", "screenshot.result.read_no_content", fallback: "result read No content")
        /// Select text to read aloud
        internal static let readSelectPrompt = ScreenshotL10n.tr("Localizable", "screenshot.result.read_select_prompt", fallback: "Select text to read aloud")
        /// Reading stopped
        internal static let readStopped = ScreenshotL10n.tr("Localizable", "screenshot.result.read_stopped", fallback: "Reading stopped")
        /// result reading
        internal static let reading = ScreenshotL10n.tr("Localizable", "screenshot.result.reading", fallback: "result reading")
        /// result summarizing
        internal static let summarizing = ScreenshotL10n.tr("Localizable", "screenshot.result.summarizing", fallback: "result summarizing")
        /// Summary cancelled
        internal static let summaryCancelled = ScreenshotL10n.tr("Localizable", "screenshot.result.summary_cancelled", fallback: "Summary cancelled")
        /// Summary complete
        internal static let summaryCompleted = ScreenshotL10n.tr("Localizable", "screenshot.result.summary_completed", fallback: "Summary complete")
        /// Summary partially completed: %@
        internal static func summaryPartialFormat(_ p1: Any) -> String {
          return ScreenshotL10n.tr("Localizable", "screenshot.result.summary_partial_format", String(describing: p1), fallback: "Summary partially completed: %@")
        }
        /// result translating
        internal static let translating = ScreenshotL10n.tr("Localizable", "screenshot.result.translating", fallback: "result translating")
        /// Translation complete
        internal static let translationCompleted = ScreenshotL10n.tr("Localizable", "screenshot.result.translation_completed", fallback: "Translation complete")
        /// Translation partially completed: %@
        internal static func translationPartialFormat(_ p1: Any) -> String {
          return ScreenshotL10n.tr("Localizable", "screenshot.result.translation_partial_format", String(describing: p1), fallback: "Translation partially completed: %@")
        }
        internal enum Error {
          /// No translation was produced.
          internal static let translationEmpty = ScreenshotL10n.tr("Localizable", "screenshot.result.error.translation_empty", fallback: "No translation was produced.")
        }
      }
    }
    internal enum Selection {
      internal enum Action {
        /// Task Assistant
        internal static let agentCompose = ScreenshotL10n.tr("Localizable", "selection.action.agent_compose", fallback: "Task Assistant")
        /// Ask AI
        internal static let askAi = ScreenshotL10n.tr("Localizable", "selection.action.ask_ai", fallback: "Ask AI")
        /// Copy
        internal static let copyText = ScreenshotL10n.tr("Localizable", "selection.action.copy_text", fallback: "Copy")
        /// Insert New Line
        internal static let insertNewLine = ScreenshotL10n.tr("Localizable", "selection.action.insert_new_line", fallback: "Insert New Line")
        /// Read Aloud
        internal static let read = ScreenshotL10n.tr("Localizable", "selection.action.read", fallback: "Read Aloud")
        /// Replace Source
        internal static let replaceSource = ScreenshotL10n.tr("Localizable", "selection.action.replace_source", fallback: "Replace Source")
        /// Summarize
        internal static let summarize = ScreenshotL10n.tr("Localizable", "selection.action.summarize", fallback: "Summarize")
        /// Translate
        internal static let translate = ScreenshotL10n.tr("Localizable", "selection.action.translate", fallback: "Translate")
      }
      internal enum Operation {
        /// Summary cancelled.
        internal static let summaryCancelled = ScreenshotL10n.tr("Localizable", "selection.operation.summary_cancelled", fallback: "Summary cancelled.")
        /// Summary completed.
        internal static let summaryCompleted = ScreenshotL10n.tr("Localizable", "selection.operation.summary_completed", fallback: "Summary completed.")
        /// Summary failed
        internal static let summaryFailedPrefix = ScreenshotL10n.tr("Localizable", "selection.operation.summary_failed_prefix", fallback: "Summary failed")
        /// Summarizing...
        internal static let summaryRunning = ScreenshotL10n.tr("Localizable", "selection.operation.summary_running", fallback: "Summarizing...")
        /// Translation cancelled.
        internal static let translationCancelled = ScreenshotL10n.tr("Localizable", "selection.operation.translation_cancelled", fallback: "Translation cancelled.")
        /// Translation completed.
        internal static let translationCompleted = ScreenshotL10n.tr("Localizable", "selection.operation.translation_completed", fallback: "Translation completed.")
        /// Translation failed
        internal static let translationFailedPrefix = ScreenshotL10n.tr("Localizable", "selection.operation.translation_failed_prefix", fallback: "Translation failed")
        /// Translating...
        internal static let translationRunning = ScreenshotL10n.tr("Localizable", "selection.operation.translation_running", fallback: "Translating...")
      }
      internal enum Panel {
        internal enum OperationTitle {
          /// Selection Summary
          internal static let summary = ScreenshotL10n.tr("Localizable", "selection.panel.operation_title.summary", fallback: "Selection Summary")
          /// Selection Translation
          internal static let translation = ScreenshotL10n.tr("Localizable", "selection.panel.operation_title.translation", fallback: "Selection Translation")
        }
        internal enum Tab {
          /// Result
          internal static let result = ScreenshotL10n.tr("Localizable", "selection.panel.tab.result", fallback: "Result")
          /// Original
          internal static let source = ScreenshotL10n.tr("Localizable", "selection.panel.tab.source", fallback: "Original")
          /// Summarize
          internal static let summary = ScreenshotL10n.tr("Localizable", "selection.panel.tab.summary", fallback: "Summarize")
          /// Translate
          internal static let translation = ScreenshotL10n.tr("Localizable", "selection.panel.tab.translation", fallback: "Translate")
        }
        internal enum Title {
          /// Result
          internal static let result = ScreenshotL10n.tr("Localizable", "selection.panel.title.result", fallback: "Result")
        }
      }
      internal enum Status {
        /// Copied.
        internal static let copied = ScreenshotL10n.tr("Localizable", "selection.status.copied", fallback: "Copied.")
        /// Copy failed.
        internal static let copyFailed = ScreenshotL10n.tr("Localizable", "selection.status.copy_failed", fallback: "Copy failed.")
        /// Inserted new line.
        internal static let insertedNewline = ScreenshotL10n.tr("Localizable", "selection.status.inserted_newline", fallback: "Inserted new line.")
        /// No valid text to process.
        internal static let noProcessableText = ScreenshotL10n.tr("Localizable", "selection.status.no_processable_text", fallback: "No valid text to process.")
        /// No text to read.
        internal static let noTextToRead = ScreenshotL10n.tr("Localizable", "selection.status.no_text_to_read", fallback: "No text to read.")
        /// No text to write.
        internal static let noTextToWrite = ScreenshotL10n.tr("Localizable", "selection.status.no_text_to_write", fallback: "No text to write.")
        /// Reading complete.
        internal static let readComplete = ScreenshotL10n.tr("Localizable", "selection.status.read_complete", fallback: "Reading complete.")
        /// Reading...
        internal static let reading = ScreenshotL10n.tr("Localizable", "selection.status.reading", fallback: "Reading...")
        /// Replaced original text.
        internal static let replacedOriginal = ScreenshotL10n.tr("Localizable", "selection.status.replaced_original", fallback: "Replaced original text.")
        /// Stopped reading.
        internal static let stopReading = ScreenshotL10n.tr("Localizable", "selection.status.stop_reading", fallback: "Stopped reading.")
        /// Write failed.
        internal static let writeFailed = ScreenshotL10n.tr("Localizable", "selection.status.write_failed", fallback: "Write failed.")
        /// Copied to clipboard as fallback.
        internal static let writeFallbackCopied = ScreenshotL10n.tr("Localizable", "selection.status.write_fallback_copied", fallback: "Copied to clipboard as fallback.")
      }
      internal enum TextProvider {
        /// Could not obtain text by accessibility.
        internal static let accessibilityNoText = ScreenshotL10n.tr("Localizable", "selection.text_provider.accessibility_no_text", fallback: "Could not obtain text by accessibility.")
        /// Could not extract text from browser content.
        internal static let browserNoText = ScreenshotL10n.tr("Localizable", "selection.text_provider.browser_no_text", fallback: "Could not extract text from browser content.")
        /// No text copied from menu.
        internal static let menuCopyNoText = ScreenshotL10n.tr("Localizable", "selection.text_provider.menu_copy_no_text", fallback: "No text copied from menu.")
        /// ===== Selection =====
        internal static let noSelectedText = ScreenshotL10n.tr("Localizable", "selection.text_provider.no_selected_text", fallback: "No text selected.")
        /// Please select text in another app and retry.
        internal static let selectTextFromOtherApp = ScreenshotL10n.tr("Localizable", "selection.text_provider.select_text_from_other_app", fallback: "Please select text in another app and retry.")
        /// No text copied by shortcut.
        internal static let shortcutCopyNoText = ScreenshotL10n.tr("Localizable", "selection.text_provider.shortcut_copy_no_text", fallback: "No text copied by shortcut.")
      }
    }
    internal enum Settings {
      /// Automatically start VoxFlow when logging in.
      internal static let launchAtLoginDescription = ScreenshotL10n.tr("Localizable", "settings.launch_at_login_description", fallback: "Automatically start VoxFlow when logging in.")
      internal enum Agent {
        internal enum Mcp {
          /// Command: %@
          /// Args: %@
          /// Config: %@
          /// Log: %@
          /// Last seen: %@
          /// Last report: %@
          /// Last request: %@
          /// Last error: %@
          ///
          /// %@
          internal static func diagnosticsFormat(_ p1: Any, _ p2: Any, _ p3: Any, _ p4: Any, _ p5: Any, _ p6: Any, _ p7: Any, _ p8: Any, _ p9: Any) -> String {
            return ScreenshotL10n.tr("Localizable", "settings.agent.mcp.diagnostics_format", String(describing: p1), String(describing: p2), String(describing: p3), String(describing: p4), String(describing: p5), String(describing: p6), String(describing: p7), String(describing: p8), String(describing: p9), fallback: "Command: %@\nArgs: %@\nConfig: %@\nLog: %@\nLast seen: %@\nLast report: %@\nLast request: %@\nLast error: %@\n\n%@")
          }
        }
      }
      internal enum AgentCli {
        /// Install voxflow/vox command links and append to shell profile:
        internal static let registerConfirmationMessage = ScreenshotL10n.tr("Localizable", "settings.agent_cli.register_confirmation_message", fallback: "Install voxflow/vox command links and append to shell profile:")
        /// Uninstall VoxFlow managed voxflow/vox command links and remove VoxFlow PATH entries from shell profile path:
        internal static let unregisterConfirmationMessage = ScreenshotL10n.tr("Localizable", "settings.agent_cli.unregister_confirmation_message", fallback: "Uninstall VoxFlow managed voxflow/vox command links and remove VoxFlow PATH entries from shell profile path:")
      }
      internal enum Appearance {
        /// Adjust menu bar, Dock, and recording indicator behavior.
        internal static let groupSubtitle = ScreenshotL10n.tr("Localizable", "settings.appearance.group_subtitle", fallback: "Adjust menu bar, Dock, and recording indicator behavior.")
        /// appearance
        internal static let groupTitle = ScreenshotL10n.tr("Localizable", "settings.appearance.group_title", fallback: "appearance")
        /// Launch at login
        internal static let launchAtLoginTitle = ScreenshotL10n.tr("Localizable", "settings.appearance.launch_at_login_title", fallback: "Launch at login")
        internal enum CapsLockIndicator {
          /// Show the Caps Lock recording indicator.
          internal static let subtitle = ScreenshotL10n.tr("Localizable", "settings.appearance.caps_lock_indicator.subtitle", fallback: "Show the Caps Lock recording indicator.")
          /// appearance Caps Lock indicator
          internal static let title = ScreenshotL10n.tr("Localizable", "settings.appearance.caps_lock_indicator.title", fallback: "appearance Caps Lock indicator")
        }
        internal enum DarkMode {
          /// Follow the system appearance or use dark mode.
          internal static let subtitle = ScreenshotL10n.tr("Localizable", "settings.appearance.dark_mode.subtitle", fallback: "Follow the system appearance or use dark mode.")
          /// appearance dark mode
          internal static let title = ScreenshotL10n.tr("Localizable", "settings.appearance.dark_mode.title", fallback: "appearance dark mode")
        }
        internal enum GrayMenuBarIcon {
          /// Use a gray menu bar icon.
          internal static let subtitle = ScreenshotL10n.tr("Localizable", "settings.appearance.gray_menu_bar_icon.subtitle", fallback: "Use a gray menu bar icon.")
          /// appearance gray menu bar icon
          internal static let title = ScreenshotL10n.tr("Localizable", "settings.appearance.gray_menu_bar_icon.title", fallback: "appearance gray menu bar icon")
        }
        internal enum HideDockIcon {
          /// Hide the Dock icon and keep the menu bar entry.
          internal static let subtitle = ScreenshotL10n.tr("Localizable", "settings.appearance.hide_dock_icon.subtitle", fallback: "Hide the Dock icon and keep the menu bar entry.")
          /// Hide Dock icon
          internal static let title = ScreenshotL10n.tr("Localizable", "settings.appearance.hide_dock_icon.title", fallback: "Hide Dock icon")
        }
      }
      internal enum Audio {
        /// Improve voice clarity.
        internal static let voiceEnhancementSubtitle = ScreenshotL10n.tr("Localizable", "settings.audio.voice_enhancement_subtitle", fallback: "Improve voice clarity.")
        /// audio voice enhancement
        internal static let voiceEnhancementTitle = ScreenshotL10n.tr("Localizable", "settings.audio.voice_enhancement_title", fallback: "audio voice enhancement")
        internal enum EnableEnhancement {
          /// Improve captured audio before recognition.
          internal static let subtitle = ScreenshotL10n.tr("Localizable", "settings.audio.enable_enhancement.subtitle", fallback: "Improve captured audio before recognition.")
          /// Audio enhancement
          internal static let title = ScreenshotL10n.tr("Localizable", "settings.audio.enable_enhancement.title", fallback: "Audio enhancement")
        }
        internal enum FeedbackTone {
          /// Play a tone when recording starts and stops.
          internal static let subtitle = ScreenshotL10n.tr("Localizable", "settings.audio.feedback_tone.subtitle", fallback: "Play a tone when recording starts and stops.")
          /// audio tone
          internal static let title = ScreenshotL10n.tr("Localizable", "settings.audio.feedback_tone.title", fallback: "audio tone")
        }
        internal enum GroupFeedback {
          /// Configure recording feedback and audio processing.
          internal static let subtitle = ScreenshotL10n.tr("Localizable", "settings.audio.group_feedback.subtitle", fallback: "Configure recording feedback and audio processing.")
          /// audio
          internal static let title = ScreenshotL10n.tr("Localizable", "settings.audio.group_feedback.title", fallback: "audio")
        }
        internal enum MuteToggle {
          /// Mute system output while recording when needed.
          internal static let subtitle = ScreenshotL10n.tr("Localizable", "settings.audio.mute_toggle.subtitle", fallback: "Mute system output while recording when needed.")
          /// Mute during recording
          internal static let title = ScreenshotL10n.tr("Localizable", "settings.audio.mute_toggle.title", fallback: "Mute during recording")
        }
      }
      internal enum AudioInput {
        /// System default input
        internal static let defaultSystemDevice = ScreenshotL10n.tr("Localizable", "settings.audio_input.default_system_device", fallback: "System default input")
        /// Unknown device
        internal static let unknownDevice = ScreenshotL10n.tr("Localizable", "settings.audio_input.unknown_device", fallback: "Unknown device")
      }
      internal enum Data {
        /// Clear history
        internal static let clearHistory = ScreenshotL10n.tr("Localizable", "settings.data.clear_history", fallback: "Clear history")
        /// Keep local crash reports for troubleshooting.
        internal static let crashReportSubtitle = ScreenshotL10n.tr("Localizable", "settings.data.crash_report_subtitle", fallback: "Keep local crash reports for troubleshooting.")
        /// Crash reports
        internal static let crashReportTitle = ScreenshotL10n.tr("Localizable", "settings.data.crash_report_title", fallback: "Crash reports")
        /// Delete all local models
        internal static let deleteAllLocalModels = ScreenshotL10n.tr("Localizable", "settings.data.delete_all_local_models", fallback: "Delete all local models")
        /// Export data
        internal static let exportData = ScreenshotL10n.tr("Localizable", "settings.data.export_data", fallback: "Export data")
        /// Manage local history, settings, and model storage.
        internal static let groupSubtitle = ScreenshotL10n.tr("Localizable", "settings.data.group_subtitle", fallback: "Manage local history, settings, and model storage.")
        /// Data
        internal static let groupTitle = ScreenshotL10n.tr("Localizable", "settings.data.group_title", fallback: "Data")
        /// Import settings
        internal static let importSettings = ScreenshotL10n.tr("Localizable", "settings.data.import_settings", fallback: "Import settings")
        /// Open data folder
        internal static let openFolder = ScreenshotL10n.tr("Localizable", "settings.data.open_folder", fallback: "Open data folder")
        /// Open support folder
        internal static let openSupportFolder = ScreenshotL10n.tr("Localizable", "settings.data.open_support_folder", fallback: "Open support folder")
        /// Refresh
        internal static let refresh = ScreenshotL10n.tr("Localizable", "settings.data.refresh", fallback: "Refresh")
        /// Refresh storage status
        internal static let refreshHelp = ScreenshotL10n.tr("Localizable", "settings.data.refresh_help", fallback: "Refresh storage status")
        /// Reset settings
        internal static let resetSettings = ScreenshotL10n.tr("Localizable", "settings.data.reset_settings", fallback: "Reset settings")
      }
      internal enum Error {
        /// This shortcut is already in use.
        internal static let duplicateShortcut = ScreenshotL10n.tr("Localizable", "settings.error.duplicate_shortcut", fallback: "This shortcut is already in use.")
        /// Invalid settings import: %@
        internal static func invalidImportFormat(_ p1: Any) -> String {
          return ScreenshotL10n.tr("Localizable", "settings.error.invalid_import_format", String(describing: p1), fallback: "Invalid settings import: %@")
        }
        /// Unable to update launch at login.
        internal static let launchAtLoginFailed = ScreenshotL10n.tr("Localizable", "settings.error.launch_at_login_failed", fallback: "Unable to update launch at login.")
        /// Data directory is unavailable.
        internal static let noDataDirectory = ScreenshotL10n.tr("Localizable", "settings.error.no_data_directory", fallback: "Data directory is unavailable.")
        /// Shortcut recording failed.
        internal static let shortcutRecordFailed = ScreenshotL10n.tr("Localizable", "settings.error.shortcut_record_failed", fallback: "Shortcut recording failed.")
        /// Voice shortcuts support Command, Option, Control, or Shift by themselves, or combinations that include those modifiers.
        internal static let unsupportedShortcut = ScreenshotL10n.tr("Localizable", "settings.error.unsupported_shortcut", fallback: "Voice shortcuts support Command, Option, Control, or Shift by themselves, or combinations that include those modifiers.")
        /// This workflow does not support custom shortcuts yet.
        internal static let unsupportedWorkflowShortcut = ScreenshotL10n.tr("Localizable", "settings.error.unsupported_workflow_shortcut", fallback: "This workflow does not support custom shortcuts yet.")
      }
      internal enum General {
        /// Shortcut conflict. Please set different keys for the two actions.
        internal static let shortcutConflict = ScreenshotL10n.tr("Localizable", "settings.general.shortcut_conflict", fallback: "Shortcut conflict. Please set different keys for the two actions.")
        /// Only affects the press-and-hold / single-press behavior of the voice shortcut
        internal static let shortcutHelp = ScreenshotL10n.tr("Localizable", "settings.general.shortcut_help", fallback: "Only affects the press-and-hold / single-press behavior of the voice shortcut")
        internal enum AgentCompose {
          /// No auto-send
          internal static let badge = ScreenshotL10n.tr("Localizable", "settings.general.agent_compose.badge", fallback: "No auto-send")
          /// Set Shortcut
          internal static let buttonTitle = ScreenshotL10n.tr("Localizable", "settings.general.agent_compose.button_title", fallback: "Set Shortcut")
          /// Compose text with current window context and voice, write directly to the current input field
          internal static let subtitle = ScreenshotL10n.tr("Localizable", "settings.general.agent_compose.subtitle", fallback: "Compose text with current window context and voice, write directly to the current input field")
          /// AI Assistant
          internal static let title = ScreenshotL10n.tr("Localizable", "settings.general.agent_compose.title", fallback: "AI Assistant")
        }
        internal enum Dictation {
          /// Modify
          internal static let buttonTitle = ScreenshotL10n.tr("Localizable", "settings.general.dictation.button_title", fallback: "Modify")
          /// Hold the shortcut to speak, release to transcribe and input
          internal static let subtitle = ScreenshotL10n.tr("Localizable", "settings.general.dictation.subtitle", fallback: "Hold the shortcut to speak, release to transcribe and input")
          /// Dictation
          internal static let title = ScreenshotL10n.tr("Localizable", "settings.general.dictation.title", fallback: "Dictation")
        }
        internal enum MiddleMouse {
          /// Click the middle mouse button to start recording, click again to stop and input
          internal static let subtitle = ScreenshotL10n.tr("Localizable", "settings.general.middle_mouse.subtitle", fallback: "Click the middle mouse button to start recording, click again to stop and input")
          /// Middle Click Recording
          internal static let title = ScreenshotL10n.tr("Localizable", "settings.general.middle_mouse.title", fallback: "Middle Click Recording")
        }
        internal enum Shortcuts {
          /// Customize global shortcuts and trigger behavior
          internal static let subtitle = ScreenshotL10n.tr("Localizable", "settings.general.shortcuts.subtitle", fallback: "Customize global shortcuts and trigger behavior")
          /// ===== Settings — General — Shortcuts (example) =====
          internal static let title = ScreenshotL10n.tr("Localizable", "settings.general.shortcuts.title", fallback: "Shortcuts")
        }
        internal enum TriggerMode {
          /// Hold
          internal static let hold = ScreenshotL10n.tr("Localizable", "settings.general.trigger_mode.hold", fallback: "Hold")
          /// Trigger Mode
          internal static let title = ScreenshotL10n.tr("Localizable", "settings.general.trigger_mode.title", fallback: "Trigger Mode")
          /// Toggle
          internal static let toggle = ScreenshotL10n.tr("Localizable", "settings.general.trigger_mode.toggle", fallback: "Toggle")
        }
        internal enum VoiceShortcut {
          /// Global entry for voice input and AI coding
          internal static let subtitle = ScreenshotL10n.tr("Localizable", "settings.general.voice_shortcut.subtitle", fallback: "Global entry for voice input and AI coding")
          /// Voice Shortcuts
          internal static let title = ScreenshotL10n.tr("Localizable", "settings.general.voice_shortcut.title", fallback: "Voice Shortcuts")
        }
        internal enum WorkflowPalette {
          /// Open VoxFlow Palette to search recent assets and commands
          internal static let subtitle = ScreenshotL10n.tr("Localizable", "settings.general.workflow_palette.subtitle", fallback: "Open VoxFlow Palette to search recent assets and commands")
        }
      }
      internal enum InterfaceLanguage {
        /// Follow System
        internal static let followSystem = ScreenshotL10n.tr("Localizable", "settings.interface_language.follow_system", fallback: "Follow System")
        /// Takes effect after restarting VoxFlow
        internal static let restartPrompt = ScreenshotL10n.tr("Localizable", "settings.interface_language.restart_prompt", fallback: "Takes effect after restarting VoxFlow")
        /// Choose the app display language
        internal static let subtitle = ScreenshotL10n.tr("Localizable", "settings.interface_language.subtitle", fallback: "Choose the app display language")
        /// ===== Interface language settings =====
        internal static let title = ScreenshotL10n.tr("Localizable", "settings.interface_language.title", fallback: "Interface Language")
        internal enum RestartDialog {
          /// VoxFlow will restart now and switch to %@. Confirm this change?
          internal static func messageFormat(_ p1: Any) -> String {
            return ScreenshotL10n.tr("Localizable", "settings.interface_language.restart_dialog.message_format", String(describing: p1), fallback: "VoxFlow will restart now and switch to %@. Confirm this change?")
          }
          /// Change interface language?
          internal static let title = ScreenshotL10n.tr("Localizable", "settings.interface_language.restart_dialog.title", fallback: "Change interface language?")
        }
      }
      internal enum Message {
        /// %@ shortcut updated
        internal static func actionShortcutUpdatedFormat(_ p1: Any) -> String {
          return ScreenshotL10n.tr("Localizable", "settings.message.action_shortcut_updated_format", String(describing: p1), fallback: "%@ shortcut updated")
        }
        /// agent alias cleared
        internal static let agentAliasCleared = ScreenshotL10n.tr("Localizable", "settings.message.agent_alias_cleared", fallback: "agent alias cleared")
        /// Agent alias deleted
        internal static let agentAliasDeleted = ScreenshotL10n.tr("Localizable", "settings.message.agent_alias_deleted", fallback: "Agent alias deleted")
        /// Agent alias saved
        internal static let agentAliasSaved = ScreenshotL10n.tr("Localizable", "settings.message.agent_alias_saved", fallback: "Agent alias saved")
        /// agent alias Updated
        internal static let agentAliasUpdated = ScreenshotL10n.tr("Localizable", "settings.message.agent_alias_updated", fallback: "agent alias Updated")
        /// Agent CLI command copied
        internal static let agentCliCommandCopied = ScreenshotL10n.tr("Localizable", "settings.message.agent_cli_command_copied", fallback: "Agent CLI command copied")
        /// Agent CLI registered
        internal static let agentCliRegistered = ScreenshotL10n.tr("Localizable", "settings.message.agent_cli_registered", fallback: "Agent CLI registered")
        /// Agent CLI registered. Restart your shell or reload your profile to use it.
        internal static let agentCliRegisteredShellHint = ScreenshotL10n.tr("Localizable", "settings.message.agent_cli_registered_shell_hint", fallback: "Agent CLI registered. Restart your shell or reload your profile to use it.")
        /// Agent CLI unregistered
        internal static let agentCliUnregistered = ScreenshotL10n.tr("Localizable", "settings.message.agent_cli_unregistered", fallback: "Agent CLI unregistered")
        /// Task assistant disabled
        internal static let agentDispatchDisabled = ScreenshotL10n.tr("Localizable", "settings.message.agent_dispatch_disabled", fallback: "Task assistant disabled")
        /// Task assistant enabled
        internal static let agentDispatchEnabled = ScreenshotL10n.tr("Localizable", "settings.message.agent_dispatch_enabled", fallback: "Task assistant enabled")
        /// Direct send enabled
        internal static let agentDispatchExactSend = ScreenshotL10n.tr("Localizable", "settings.message.agent_dispatch_exact_send", fallback: "Direct send enabled")
        /// MCP status updated
        internal static let agentDispatchMcp = ScreenshotL10n.tr("Localizable", "settings.message.agent_dispatch_mcp", fallback: "MCP status updated")
        /// Agent target behavior updated
        internal static let agentDispatchUnresolvedBehavior = ScreenshotL10n.tr("Localizable", "settings.message.agent_dispatch_unresolved_behavior", fallback: "Agent target behavior updated")
        /// agent launch command Copied
        internal static let agentLaunchCommandCopied = ScreenshotL10n.tr("Localizable", "settings.message.agent_launch_command_copied", fallback: "agent launch command Copied")
        /// Agent session stopped
        internal static let agentSessionStopped = ScreenshotL10n.tr("Localizable", "settings.message.agent_session_stopped", fallback: "Agent session stopped")
        /// All local models deleted
        internal static let allModelsDeleted = ScreenshotL10n.tr("Localizable", "settings.message.all_models_deleted", fallback: "All local models deleted")
        /// Analytics settings updated
        internal static let analyticsSettingsUpdated = ScreenshotL10n.tr("Localizable", "settings.message.analytics_settings_updated", fallback: "Analytics settings updated")
        /// Audio settings updated
        internal static let audioSettingsUpdated = ScreenshotL10n.tr("Localizable", "settings.message.audio_settings_updated", fallback: "Audio settings updated")
        /// dispatch Log cleared
        internal static let dispatchLogCleared = ScreenshotL10n.tr("Localizable", "settings.message.dispatch_log_cleared", fallback: "dispatch Log cleared")
        /// Data export prepared
        internal static let exportDataGenerated = ScreenshotL10n.tr("Localizable", "settings.message.export_data_generated", fallback: "Data export prepared")
        /// history cleared
        internal static let historyCleared = ScreenshotL10n.tr("Localizable", "settings.message.history_cleared", fallback: "history cleared")
        /// input Device Updated
        internal static let inputDeviceUpdated = ScreenshotL10n.tr("Localizable", "settings.message.input_device_updated", fallback: "input Device Updated")
        /// local data folder opened
        internal static let localDataFolderOpened = ScreenshotL10n.tr("Localizable", "settings.message.local_data_folder_opened", fallback: "local data folder opened")
        /// MCP diagnostics cleared
        internal static let mcpDiagnosticsCleared = ScreenshotL10n.tr("Localizable", "settings.message.mcp_diagnostics_cleared", fallback: "MCP diagnostics cleared")
        /// MCP diagnostics copied
        internal static let mcpDiagnosticsCopied = ScreenshotL10n.tr("Localizable", "settings.message.mcp_diagnostics_copied", fallback: "MCP diagnostics copied")
        /// MCP log is empty
        internal static let mcpLogEmpty = ScreenshotL10n.tr("Localizable", "settings.message.mcp_log_empty", fallback: "MCP log is empty")
        /// MCP log has not been created yet
        internal static let mcpLogNotCreated = ScreenshotL10n.tr("Localizable", "settings.message.mcp_log_not_created", fallback: "MCP log has not been created yet")
        /// MCP log is not valid UTF-8 text
        internal static let mcpLogNotUtf8 = ScreenshotL10n.tr("Localizable", "settings.message.mcp_log_not_utf8", fallback: "MCP log is not valid UTF-8 text")
        /// Failed to open MCP log
        internal static let mcpLogOpenFailed = ScreenshotL10n.tr("Localizable", "settings.message.mcp_log_open_failed", fallback: "Failed to open MCP log")
        /// MCP log opened
        internal static let mcpLogOpened = ScreenshotL10n.tr("Localizable", "settings.message.mcp_log_opened", fallback: "MCP log opened")
        /// MCP log path is missing
        internal static let mcpLogPathMissing = ScreenshotL10n.tr("Localizable", "settings.message.mcp_log_path_missing", fallback: "MCP log path is missing")
        /// Failed to read MCP log
        internal static let mcpLogReadFailed = ScreenshotL10n.tr("Localizable", "settings.message.mcp_log_read_failed", fallback: "Failed to read MCP log")
        /// Middle mouse recording disabled
        internal static let middleMouseRecordingDisabled = ScreenshotL10n.tr("Localizable", "settings.message.middle_mouse_recording_disabled", fallback: "Middle mouse recording disabled")
        /// Middle mouse recording enabled
        internal static let middleMouseRecordingEnabled = ScreenshotL10n.tr("Localizable", "settings.message.middle_mouse_recording_enabled", fallback: "Middle mouse recording enabled")
        /// Recognition language updated
        internal static let recognitionLanguageUpdated = ScreenshotL10n.tr("Localizable", "settings.message.recognition_language_updated", fallback: "Recognition language updated")
        /// settings imported
        internal static let settingsImported = ScreenshotL10n.tr("Localizable", "settings.message.settings_imported", fallback: "settings imported")
        /// settings reset
        internal static let settingsReset = ScreenshotL10n.tr("Localizable", "settings.message.settings_reset", fallback: "settings reset")
        /// Shortcut applied
        internal static let shortcutApplied = ScreenshotL10n.tr("Localizable", "settings.message.shortcut_applied", fallback: "Shortcut applied")
        /// shortcuts Updated
        internal static let shortcutsUpdated = ScreenshotL10n.tr("Localizable", "settings.message.shortcuts_updated", fallback: "shortcuts Updated")
        /// stale agent sessions cleared
        internal static let staleAgentSessionsCleared = ScreenshotL10n.tr("Localizable", "settings.message.stale_agent_sessions_cleared", fallback: "stale agent sessions cleared")
        /// System settings updated
        internal static let systemSettingsUpdated = ScreenshotL10n.tr("Localizable", "settings.message.system_settings_updated", fallback: "System settings updated")
        /// text input mode Updated
        internal static let textInputModeUpdated = ScreenshotL10n.tr("Localizable", "settings.message.text_input_mode_updated", fallback: "text input mode Updated")
        /// unknown storage size
        internal static let unknownStorageSize = ScreenshotL10n.tr("Localizable", "settings.message.unknown_storage_size", fallback: "unknown storage size")
        /// voice correction auto apply immediate
        internal static let voiceCorrectionAutoApplyImmediate = ScreenshotL10n.tr("Localizable", "settings.message.voice_correction_auto_apply_immediate", fallback: "voice correction auto apply immediate")
        /// voice correction auto apply pending
        internal static let voiceCorrectionAutoApplyPending = ScreenshotL10n.tr("Localizable", "settings.message.voice_correction_auto_apply_pending", fallback: "voice correction auto apply pending")
        /// voice correction auto learning disabled
        internal static let voiceCorrectionAutoLearningDisabled = ScreenshotL10n.tr("Localizable", "settings.message.voice_correction_auto_learning_disabled", fallback: "voice correction auto learning disabled")
        /// voice correction auto learning enabled
        internal static let voiceCorrectionAutoLearningEnabled = ScreenshotL10n.tr("Localizable", "settings.message.voice_correction_auto_learning_enabled", fallback: "voice correction auto learning enabled")
        /// voice correction disabled
        internal static let voiceCorrectionDisabled = ScreenshotL10n.tr("Localizable", "settings.message.voice_correction_disabled", fallback: "voice correction disabled")
        /// voice correction enabled
        internal static let voiceCorrectionEnabled = ScreenshotL10n.tr("Localizable", "settings.message.voice_correction_enabled", fallback: "voice correction enabled")
        /// voice correction shadow mode disabled
        internal static let voiceCorrectionShadowModeDisabled = ScreenshotL10n.tr("Localizable", "settings.message.voice_correction_shadow_mode_disabled", fallback: "voice correction shadow mode disabled")
        /// voice correction shadow mode enabled
        internal static let voiceCorrectionShadowModeEnabled = ScreenshotL10n.tr("Localizable", "settings.message.voice_correction_shadow_mode_enabled", fallback: "voice correction shadow mode enabled")
        /// %@ shortcut updated
        internal static func workflowShortcutUpdatedFormat(_ p1: Any) -> String {
          return ScreenshotL10n.tr("Localizable", "settings.message.workflow_shortcut_updated_format", String(describing: p1), fallback: "%@ shortcut updated")
        }
      }
      internal enum Output {
        /// Configure output.
        internal static let groupSubtitle = ScreenshotL10n.tr("Localizable", "settings.output.group_subtitle", fallback: "Configure output.")
        /// output
        internal static let groupTitle = ScreenshotL10n.tr("Localizable", "settings.output.group_title", fallback: "output")
        internal enum AvoidClipboard {
          /// Configure output avoid clipboard.
          internal static let subtitle = ScreenshotL10n.tr("Localizable", "settings.output.avoid_clipboard.subtitle", fallback: "Configure output avoid clipboard.")
          /// output avoid clipboard
          internal static let title = ScreenshotL10n.tr("Localizable", "settings.output.avoid_clipboard.title", fallback: "output avoid clipboard")
        }
        internal enum ClipboardImageOcr {
          /// Recognize text from clipboard images.
          internal static let subtitle = ScreenshotL10n.tr("Localizable", "settings.output.clipboard_image_ocr.subtitle", fallback: "Recognize text from clipboard images.")
        }
        internal enum RestoreClipboard {
          /// Configure output restore clipboard.
          internal static let subtitle = ScreenshotL10n.tr("Localizable", "settings.output.restore_clipboard.subtitle", fallback: "Configure output restore clipboard.")
          /// output restore clipboard
          internal static let title = ScreenshotL10n.tr("Localizable", "settings.output.restore_clipboard.title", fallback: "output restore clipboard")
        }
      }
      internal enum PermissionStatus {
        /// Denied
        internal static let denied = ScreenshotL10n.tr("Localizable", "settings.permission_status.denied", fallback: "Denied")
        /// Granted
        internal static let granted = ScreenshotL10n.tr("Localizable", "settings.permission_status.granted", fallback: "Granted")
        /// Not requested
        internal static let notDetermined = ScreenshotL10n.tr("Localizable", "settings.permission_status.not_determined", fallback: "Not requested")
      }
      internal enum Permissions {
        /// Allow global shortcuts and text insertion.
        internal static let accessibilitySubtitle = ScreenshotL10n.tr("Localizable", "settings.permissions.accessibility_subtitle", fallback: "Allow global shortcuts and text insertion.")
        /// Accessibility
        internal static let accessibilityTitle = ScreenshotL10n.tr("Localizable", "settings.permissions.accessibility_title", fallback: "Accessibility")
        /// Open System Settings
        internal static let gotoSettings = ScreenshotL10n.tr("Localizable", "settings.permissions.goto_settings", fallback: "Open System Settings")
        /// Grant the permissions below in macOS Privacy & Security.
        internal static let infoBody = ScreenshotL10n.tr("Localizable", "settings.permissions.info_body", fallback: "Grant the permissions below in macOS Privacy & Security.")
        /// Permissions
        internal static let infoTitle = ScreenshotL10n.tr("Localizable", "settings.permissions.info_title", fallback: "Permissions")
        /// Allow dictation and recordings to capture audio.
        internal static let microphoneSubtitle = ScreenshotL10n.tr("Localizable", "settings.permissions.microphone_subtitle", fallback: "Allow dictation and recordings to capture audio.")
        /// Microphone
        internal static let microphoneTitle = ScreenshotL10n.tr("Localizable", "settings.permissions.microphone_title", fallback: "Microphone")
        /// Allow screenshot OCR and screen recording.
        internal static let screenRecordingSubtitle = ScreenshotL10n.tr("Localizable", "settings.permissions.screen_recording_subtitle", fallback: "Allow screenshot OCR and screen recording.")
        /// Screen Recording
        internal static let screenRecordingTitle = ScreenshotL10n.tr("Localizable", "settings.permissions.screen_recording_title", fallback: "Screen Recording")
        /// Review required macOS permissions.
        internal static let sectionSubtitle = ScreenshotL10n.tr("Localizable", "settings.permissions.section_subtitle", fallback: "Review required macOS permissions.")
        /// Permissions
        internal static let sectionTitle = ScreenshotL10n.tr("Localizable", "settings.permissions.section_title", fallback: "Permissions")
        /// Allow Apple Speech recognition.
        internal static let speechSubtitle = ScreenshotL10n.tr("Localizable", "settings.permissions.speech_subtitle", fallback: "Allow Apple Speech recognition.")
        /// Speech Recognition
        internal static let speechTitle = ScreenshotL10n.tr("Localizable", "settings.permissions.speech_title", fallback: "Speech Recognition")
      }
      internal enum Privacy {
        /// Share anonymous product diagnostics.
        internal static let analyticsSubtitle = ScreenshotL10n.tr("Localizable", "settings.privacy.analytics_subtitle", fallback: "Share anonymous product diagnostics.")
        /// Analytics
        internal static let analyticsTitle = ScreenshotL10n.tr("Localizable", "settings.privacy.analytics_title", fallback: "Analytics")
        /// Keep local logs for troubleshooting.
        internal static let crashLogsSubtitle = ScreenshotL10n.tr("Localizable", "settings.privacy.crash_logs_subtitle", fallback: "Keep local logs for troubleshooting.")
        /// Crash Logs
        internal static let crashLogsTitle = ScreenshotL10n.tr("Localizable", "settings.privacy.crash_logs_title", fallback: "Crash Logs")
        /// Control local data and diagnostics.
        internal static let groupSubtitle = ScreenshotL10n.tr("Localizable", "settings.privacy.group_subtitle", fallback: "Control local data and diagnostics.")
        /// Privacy
        internal static let groupTitle = ScreenshotL10n.tr("Localizable", "settings.privacy.group_title", fallback: "Privacy")
        /// Delete LLM traces
        internal static let llmTraceDelete = ScreenshotL10n.tr("Localizable", "settings.privacy.llm_trace_delete", fallback: "Delete LLM traces")
        /// LLM traces are stored locally for debugging.
        internal static let llmTraceNotice = ScreenshotL10n.tr("Localizable", "settings.privacy.llm_trace_notice", fallback: "LLM traces are stored locally for debugging.")
        /// Review and clear local prompt diagnostics.
        internal static let llmTraceSubtitle = ScreenshotL10n.tr("Localizable", "settings.privacy.llm_trace_subtitle", fallback: "Review and clear local prompt diagnostics.")
        /// LLM Traces
        internal static let llmTraceTitle = ScreenshotL10n.tr("Localizable", "settings.privacy.llm_trace_title", fallback: "LLM Traces")
      }
      internal enum Section {
        /// Correction Models
        internal static let correctionModels = ScreenshotL10n.tr("Localizable", "settings.section.correction_models", fallback: "Correction Models")
        /// Data & Privacy
        internal static let dataPrivacy = ScreenshotL10n.tr("Localizable", "settings.section.data_privacy", fallback: "Data & Privacy")
        /// Dictation Models
        internal static let dictationModels = ScreenshotL10n.tr("Localizable", "settings.section.dictation_models", fallback: "Dictation Models")
        /// General
        internal static let general = ScreenshotL10n.tr("Localizable", "settings.section.general", fallback: "General")
        /// System
        internal static let systemRoot = ScreenshotL10n.tr("Localizable", "settings.section.system_root", fallback: "System")
        /// Translation Models
        internal static let translationModels = ScreenshotL10n.tr("Localizable", "settings.section.translation_models", fallback: "Translation Models")
        /// TTS Models
        internal static let ttsModels = ScreenshotL10n.tr("Localizable", "settings.section.tts_models", fallback: "TTS Models")
        /// Vibe Coding
        internal static let vibeCoding = ScreenshotL10n.tr("Localizable", "settings.section.vibe_coding", fallback: "Vibe Coding")
      }
      internal enum Shortcuts {
        /// Cancel
        internal static let cancel = ScreenshotL10n.tr("Localizable", "settings.shortcuts.cancel", fallback: "Cancel")
        /// Clear
        internal static let clear = ScreenshotL10n.tr("Localizable", "settings.shortcuts.clear", fallback: "Clear")
        /// Change shortcut
        internal static let modify = ScreenshotL10n.tr("Localizable", "settings.shortcuts.modify", fallback: "Change shortcut")
        /// Press a shortcut
        internal static let recording = ScreenshotL10n.tr("Localizable", "settings.shortcuts.recording", fallback: "Press a shortcut")
        /// Short press does nothing
        internal static let shortPressNoActionBehavior = ScreenshotL10n.tr("Localizable", "settings.shortcuts.short_press_no_action_behavior", fallback: "Short press does nothing")
        /// Short press toggles listening
        internal static let shortPressToggleBehavior = ScreenshotL10n.tr("Localizable", "settings.shortcuts.short_press_toggle_behavior", fallback: "Short press toggles listening")
        /// Not set
        internal static let unset = ScreenshotL10n.tr("Localizable", "settings.shortcuts.unset", fallback: "Not set")
        internal enum ClipboardImageOcr {
          /// Clipboard Image OCR
          internal static let title = ScreenshotL10n.tr("Localizable", "settings.shortcuts.clipboard_image_ocr.title", fallback: "Clipboard Image OCR")
        }
      }
      internal enum Storage {
        /// Diagnostic information is kept only in local Application Support/VoxFlow directory. VoxFlow does not automatically upload audio, transcripts, or crash logs.
        internal static let diagnosticPrivacyNotice = ScreenshotL10n.tr("Localizable", "settings.storage.diagnostic_privacy_notice", fallback: "Diagnostic information is kept only in local Application Support/VoxFlow directory. VoxFlow does not automatically upload audio, transcripts, or crash logs.")
        /// . Current database is located at
        internal static let readOnlyMessage = ScreenshotL10n.tr("Localizable", "settings.storage.read_only_message", fallback: ". Current database is located at")
        /// VoxFlow may not reliably save new history, settings, or task states. Check folder permissions, or copy your data elsewhere before repairing storage.
        internal static let readOnlyMessageSuffix = ScreenshotL10n.tr("Localizable", "settings.storage.read_only_message_suffix", fallback: "VoxFlow may not reliably save new history, settings, or task states. Check folder permissions, or copy your data elsewhere before repairing storage.")
        internal enum Badge {
          /// Corrupt
          internal static let corrupt = ScreenshotL10n.tr("Localizable", "settings.storage.badge.corrupt", fallback: "Corrupt")
          /// Migration required
          internal static let migrationRequired = ScreenshotL10n.tr("Localizable", "settings.storage.badge.migration_required", fallback: "Migration required")
          /// Normal
          internal static let normal = ScreenshotL10n.tr("Localizable", "settings.storage.badge.normal", fallback: "Normal")
          /// Read-only
          internal static let readOnly = ScreenshotL10n.tr("Localizable", "settings.storage.badge.read_only", fallback: "Read-only")
          /// Unavailable
          internal static let unavailable = ScreenshotL10n.tr("Localizable", "settings.storage.badge.unavailable", fallback: "Unavailable")
          /// Session only
          internal static let volatile = ScreenshotL10n.tr("Localizable", "settings.storage.badge.volatile", fallback: "Session only")
        }
        internal enum Message {
          /// %@ The database may be corrupt. Export or back up your data before repairing it.
          internal static func corrupt(_ p1: Any) -> String {
            return ScreenshotL10n.tr("Localizable", "settings.storage.message.corrupt", String(describing: p1), fallback: "%@ The database may be corrupt. Export or back up your data before repairing it.")
          }
          /// %@ Avoid writing new data until migration finishes.
          internal static func migrationRequired(_ p1: Any) -> String {
            return ScreenshotL10n.tr("Localizable", "settings.storage.message.migration_required", String(describing: p1), fallback: "%@ Avoid writing new data until migration finishes.")
          }
          /// Data is saved in %@.
          internal static func persistent(_ p1: Any) -> String {
            return ScreenshotL10n.tr("Localizable", "settings.storage.message.persistent", String(describing: p1), fallback: "Data is saved in %@.")
          }
          /// %@ Changes last only for this session and may be lost after restart.
          internal static func sessionOnly(_ p1: Any) -> String {
            return ScreenshotL10n.tr("Localizable", "settings.storage.message.session_only", String(describing: p1), fallback: "%@ Changes last only for this session and may be lost after restart.")
          }
          /// %@ Changes are kept in temporary storage only and may be lost after restart.
          internal static func unavailable(_ p1: Any) -> String {
            return ScreenshotL10n.tr("Localizable", "settings.storage.message.unavailable", String(describing: p1), fallback: "%@ Changes are kept in temporary storage only and may be lost after restart.")
          }
          /// %@ Changes are kept in temporary storage only and may be lost after restart.
          internal static func volatile(_ p1: Any) -> String {
            return ScreenshotL10n.tr("Localizable", "settings.storage.message.volatile", String(describing: p1), fallback: "%@ Changes are kept in temporary storage only and may be lost after restart.")
          }
          /// %@ Storage status: %@. Persistence is not guaranteed.
          internal static func warning(_ p1: Any, _ p2: Any) -> String {
            return ScreenshotL10n.tr("Localizable", "settings.storage.message.warning", String(describing: p1), String(describing: p2), fallback: "%@ Storage status: %@. Persistence is not guaranteed.")
          }
        }
        internal enum Title {
          /// Storage is corrupt
          internal static let corrupt = ScreenshotL10n.tr("Localizable", "settings.storage.title.corrupt", fallback: "Storage is corrupt")
          /// Storage migration required
          internal static let migrationRequired = ScreenshotL10n.tr("Localizable", "settings.storage.title.migration_required", fallback: "Storage migration required")
          /// Persistent storage
          internal static let persistent = ScreenshotL10n.tr("Localizable", "settings.storage.title.persistent", fallback: "Persistent storage")
          /// Storage is read-only
          internal static let readOnly = ScreenshotL10n.tr("Localizable", "settings.storage.title.read_only", fallback: "Storage is read-only")
          /// Storage unavailable
          internal static let unavailable = ScreenshotL10n.tr("Localizable", "settings.storage.title.unavailable", fallback: "Storage unavailable")
          /// Session-only storage
          internal static let volatile = ScreenshotL10n.tr("Localizable", "settings.storage.title.volatile", fallback: "Session-only storage")
        }
      }
      internal enum System {
        /// Tune resource and runtime behavior.
        internal static let performanceSubtitle = ScreenshotL10n.tr("Localizable", "settings.system.performance_subtitle", fallback: "Tune resource and runtime behavior.")
        /// Performance
        internal static let performanceTitle = ScreenshotL10n.tr("Localizable", "settings.system.performance_title", fallback: "Performance")
        internal enum AutoReleaseLocalModel {
          /// Release local models when idle to save memory.
          internal static let subtitle = ScreenshotL10n.tr("Localizable", "settings.system.auto_release_local_model.subtitle", fallback: "Release local models when idle to save memory.")
          /// Auto-release local models
          internal static let title = ScreenshotL10n.tr("Localizable", "settings.system.auto_release_local_model.title", fallback: "Auto-release local models")
        }
        internal enum KeepMicrophoneActive {
          /// Keep the microphone warm for faster startup.
          internal static let subtitle = ScreenshotL10n.tr("Localizable", "settings.system.keep_microphone_active.subtitle", fallback: "Keep the microphone warm for faster startup.")
          /// Keep microphone active
          internal static let title = ScreenshotL10n.tr("Localizable", "settings.system.keep_microphone_active.title", fallback: "Keep microphone active")
        }
        internal enum LocalModelLivePreview {
          /// Show partial results from local models while speaking.
          internal static let subtitle = ScreenshotL10n.tr("Localizable", "settings.system.local_model_live_preview.subtitle", fallback: "Show partial results from local models while speaking.")
          /// Local model live preview
          internal static let title = ScreenshotL10n.tr("Localizable", "settings.system.local_model_live_preview.title", fallback: "Local model live preview")
        }
      }
      internal enum Task {
        /// Choose what to do when the target agent cannot be resolved.
        internal static let unresolvedBehaviorHelp = ScreenshotL10n.tr("Localizable", "settings.task.unresolved_behavior_help", fallback: "Choose what to do when the target agent cannot be resolved.")
        internal enum Action {
          /// Cancel
          internal static let cancel = ScreenshotL10n.tr("Localizable", "settings.task.action.cancel", fallback: "Cancel")
          /// Confirm
          internal static let confirm = ScreenshotL10n.tr("Localizable", "settings.task.action.confirm", fallback: "Confirm")
          /// Copy example
          internal static let copyExample = ScreenshotL10n.tr("Localizable", "settings.task.action.copy_example", fallback: "Copy example")
          /// Delete all local models
          internal static let deleteAllLocalModels = ScreenshotL10n.tr("Localizable", "settings.task.action.delete_all_local_models", fallback: "Delete all local models")
          /// Register
          internal static let register = ScreenshotL10n.tr("Localizable", "settings.task.action.register", fallback: "Register")
          /// Unregister
          internal static let unregister = ScreenshotL10n.tr("Localizable", "settings.task.action.unregister", fallback: "Unregister")
        }
        internal enum AgentCli {
          /// Claude Code
          internal static let exampleClaude = ScreenshotL10n.tr("Localizable", "settings.task.agent_cli.example_claude", fallback: "Claude Code")
          /// CodeBuddy
          internal static let exampleCodebuddy = ScreenshotL10n.tr("Localizable", "settings.task.agent_cli.example_codebuddy", fallback: "CodeBuddy")
          /// Codex
          internal static let exampleCodex = ScreenshotL10n.tr("Localizable", "settings.task.agent_cli.example_codex", fallback: "Codex")
          /// Register the bundled vox command so terminal agents can receive dictated prompts.
          internal static let intro = ScreenshotL10n.tr("Localizable", "settings.task.agent_cli.intro", fallback: "Register the bundled vox command so terminal agents can receive dictated prompts.")
          /// Registered
          internal static let registeredStatus = ScreenshotL10n.tr("Localizable", "settings.task.agent_cli.registered_status", fallback: "Registered")
          /// Registered at %@
          internal static func registeredWithPathStatus(_ p1: Any) -> String {
            return ScreenshotL10n.tr("Localizable", "settings.task.agent_cli.registered_with_path_status", String(describing: p1), fallback: "Registered at %@")
          }
          /// Agent CLI
          internal static let title = ScreenshotL10n.tr("Localizable", "settings.task.agent_cli.title", fallback: "Agent CLI")
        }
        internal enum AiConsole {
          /// Low confidence. Review before sending.
          internal static let lowConfidenceNote = ScreenshotL10n.tr("Localizable", "settings.task.ai_console.low_confidence_note", fallback: "Low confidence. Review before sending.")
          /// Configure coding-agent dispatch behavior.
          internal static let subtitle = ScreenshotL10n.tr("Localizable", "settings.task.ai_console.subtitle", fallback: "Configure coding-agent dispatch behavior.")
          /// AI Coding Console
          internal static let title = ScreenshotL10n.tr("Localizable", "settings.task.ai_console.title", fallback: "AI Coding Console")
          /// Unknown assistant
          internal static let unknownAgentName = ScreenshotL10n.tr("Localizable", "settings.task.ai_console.unknown_agent_name", fallback: "Unknown assistant")
          internal enum DirectSend {
            /// Send to a resolved assistant without an extra confirmation.
            internal static let subtitle = ScreenshotL10n.tr("Localizable", "settings.task.ai_console.direct_send.subtitle", fallback: "Send to a resolved assistant without an extra confirmation.")
            /// Direct Send
            internal static let title = ScreenshotL10n.tr("Localizable", "settings.task.ai_console.direct_send.title", fallback: "Direct Send")
          }
          internal enum Enable {
            /// Enable voice commands for local coding agents.
            internal static let subtitle = ScreenshotL10n.tr("Localizable", "settings.task.ai_console.enable.subtitle", fallback: "Enable voice commands for local coding agents.")
            /// AI Coding Assistant
            internal static let title = ScreenshotL10n.tr("Localizable", "settings.task.ai_console.enable.title", fallback: "AI Coding Assistant")
          }
          internal enum McpStatus {
            /// Expose live session diagnostics through MCP.
            internal static let subtitle = ScreenshotL10n.tr("Localizable", "settings.task.ai_console.mcp_status.subtitle", fallback: "Expose live session diagnostics through MCP.")
            /// MCP Status
            internal static let title = ScreenshotL10n.tr("Localizable", "settings.task.ai_console.mcp_status.title", fallback: "MCP Status")
          }
        }
        internal enum Correction {
          /// Manage recognition correction and vocabulary behavior.
          internal static let subtitle = ScreenshotL10n.tr("Localizable", "settings.task.correction.subtitle", fallback: "Manage recognition correction and vocabulary behavior.")
          /// Correction
          internal static let title = ScreenshotL10n.tr("Localizable", "settings.task.correction.title", fallback: "Correction")
          internal enum ContextBoost {
            /// Use temporary context from OCR and recent activity.
            internal static let subtitle = ScreenshotL10n.tr("Localizable", "settings.task.correction.context_boost.subtitle", fallback: "Use temporary context from OCR and recent activity.")
            /// Context boost
            internal static let title = ScreenshotL10n.tr("Localizable", "settings.task.correction.context_boost.title", fallback: "Context boost")
          }
          internal enum Llm {
            /// Use an LLM to conservatively correct recognition text.
            internal static let subtitle = ScreenshotL10n.tr("Localizable", "settings.task.correction.llm.subtitle", fallback: "Use an LLM to conservatively correct recognition text.")
            /// LLM correction
            internal static let title = ScreenshotL10n.tr("Localizable", "settings.task.correction.llm.title", fallback: "LLM correction")
          }
        }
        internal enum Dialog {
          internal enum DeleteAllLocalModels {
            /// Delete all local models?
            internal static let title = ScreenshotL10n.tr("Localizable", "settings.task.dialog.delete_all_local_models.title", fallback: "Delete all local models?")
          }
          internal enum RegisterCli {
            /// Register Agent CLI
            internal static let title = ScreenshotL10n.tr("Localizable", "settings.task.dialog.register_cli.title", fallback: "Register Agent CLI")
          }
          internal enum UnregisterCli {
            /// Unregister Agent CLI
            internal static let title = ScreenshotL10n.tr("Localizable", "settings.task.dialog.unregister_cli.title", fallback: "Unregister Agent CLI")
          }
        }
        internal enum Dictation {
          internal enum Section {
            /// Choose and manage speech recognition models.
            internal static let subtitle = ScreenshotL10n.tr("Localizable", "settings.task.dictation.section.subtitle", fallback: "Choose and manage speech recognition models.")
            /// Dictation
            internal static let title = ScreenshotL10n.tr("Localizable", "settings.task.dictation.section.title", fallback: "Dictation")
          }
        }
        internal enum EasyWord {
          /// Configure hotwords and text replacement.
          internal static let subtitle = ScreenshotL10n.tr("Localizable", "settings.task.easy_word.subtitle", fallback: "Configure hotwords and text replacement.")
          /// Vocabulary
          internal static let title = ScreenshotL10n.tr("Localizable", "settings.task.easy_word.title", fallback: "Vocabulary")
          internal enum AutoLearning {
            /// Learn likely correction terms from edits.
            internal static let subtitle = ScreenshotL10n.tr("Localizable", "settings.task.easy_word.auto_learning.subtitle", fallback: "Learn likely correction terms from edits.")
            /// Auto-learning
            internal static let title = ScreenshotL10n.tr("Localizable", "settings.task.easy_word.auto_learning.title", fallback: "Auto-learning")
          }
          internal enum AutoLearningImmediate {
            /// Apply high-confidence learned terms immediately.
            internal static let subtitle = ScreenshotL10n.tr("Localizable", "settings.task.easy_word.auto_learning_immediate.subtitle", fallback: "Apply high-confidence learned terms immediately.")
            /// Immediate learning
            internal static let title = ScreenshotL10n.tr("Localizable", "settings.task.easy_word.auto_learning_immediate.title", fallback: "Immediate learning")
          }
          internal enum Enable {
            /// Use deterministic replacements for known phrases.
            internal static let subtitle = ScreenshotL10n.tr("Localizable", "settings.task.easy_word.enable.subtitle", fallback: "Use deterministic replacements for known phrases.")
            /// Text replacement
            internal static let title = ScreenshotL10n.tr("Localizable", "settings.task.easy_word.enable.title", fallback: "Text replacement")
          }
          internal enum ShadowMode {
            /// Observe matches without changing output.
            internal static let subtitle = ScreenshotL10n.tr("Localizable", "settings.task.easy_word.shadow_mode.subtitle", fallback: "Observe matches without changing output.")
            /// Shadow mode
            internal static let title = ScreenshotL10n.tr("Localizable", "settings.task.easy_word.shadow_mode.title", fallback: "Shadow mode")
          }
        }
        internal enum InputDevice {
          /// Input Device
          internal static let title = ScreenshotL10n.tr("Localizable", "settings.task.input_device.title", fallback: "Input Device")
        }
        internal enum InputLanguage {
          /// Configure input, recognition, and interface language.
          internal static let subtitle = ScreenshotL10n.tr("Localizable", "settings.task.input_language.subtitle", fallback: "Configure input, recognition, and interface language.")
          /// Input & Language
          internal static let title = ScreenshotL10n.tr("Localizable", "settings.task.input_language.title", fallback: "Input & Language")
        }
        internal enum RecognitionLanguage {
          /// Recognition Language
          internal static let title = ScreenshotL10n.tr("Localizable", "settings.task.recognition_language.title", fallback: "Recognition Language")
        }
        internal enum Selection {
          internal enum Action {
            /// Enable actions for selected text.
            internal static let subtitle = ScreenshotL10n.tr("Localizable", "settings.task.selection.action.subtitle", fallback: "Enable actions for selected text.")
            /// Selection Actions
            internal static let title = ScreenshotL10n.tr("Localizable", "settings.task.selection.action.title", fallback: "Selection Actions")
          }
          internal enum Agent {
            /// Send selected text to a task assistant.
            internal static let subtitle = ScreenshotL10n.tr("Localizable", "settings.task.selection.agent.subtitle", fallback: "Send selected text to a task assistant.")
            /// Selection Assistant
            internal static let title = ScreenshotL10n.tr("Localizable", "settings.task.selection.agent.title", fallback: "Selection Assistant")
          }
          internal enum AskAi {
            /// Ask AI about selected text.
            internal static let subtitle = ScreenshotL10n.tr("Localizable", "settings.task.selection.ask_ai.subtitle", fallback: "Ask AI about selected text.")
            /// Ask AI
            internal static let title = ScreenshotL10n.tr("Localizable", "settings.task.selection.ask_ai.title", fallback: "Ask AI")
          }
          internal enum Group {
            /// Configure selected-text workflows.
            internal static let subtitle = ScreenshotL10n.tr("Localizable", "settings.task.selection.group.subtitle", fallback: "Configure selected-text workflows.")
            /// Selection
            internal static let title = ScreenshotL10n.tr("Localizable", "settings.task.selection.group.title", fallback: "Selection")
          }
          internal enum Summarize {
            /// Summarize selected text.
            internal static let subtitle = ScreenshotL10n.tr("Localizable", "settings.task.selection.summarize.subtitle", fallback: "Summarize selected text.")
            /// Summarize
            internal static let title = ScreenshotL10n.tr("Localizable", "settings.task.selection.summarize.title", fallback: "Summarize")
          }
          internal enum Translate {
            /// Translate selected text.
            internal static let subtitle = ScreenshotL10n.tr("Localizable", "settings.task.selection.translate.subtitle", fallback: "Translate selected text.")
            /// Translate
            internal static let title = ScreenshotL10n.tr("Localizable", "settings.task.selection.translate.title", fallback: "Translate")
          }
        }
        internal enum Sidebar {
          internal enum Group {
            /// App
            internal static let app = ScreenshotL10n.tr("Localizable", "settings.task.sidebar.group.app", fallback: "App")
            /// Data & Privacy
            internal static let dataPrivacy = ScreenshotL10n.tr("Localizable", "settings.task.sidebar.group.data_privacy", fallback: "Data & Privacy")
            /// Models
            internal static let models = ScreenshotL10n.tr("Localizable", "settings.task.sidebar.group.models", fallback: "Models")
          }
        }
        internal enum Translation {
          /// Configure translation behavior.
          internal static let subtitle = ScreenshotL10n.tr("Localizable", "settings.task.translation.subtitle", fallback: "Configure translation behavior.")
          /// Translation
          internal static let title = ScreenshotL10n.tr("Localizable", "settings.task.translation.title", fallback: "Translation")
        }
        internal enum Tts {
          /// Configure read-aloud voices.
          internal static let subtitle = ScreenshotL10n.tr("Localizable", "settings.task.tts.subtitle", fallback: "Configure read-aloud voices.")
          /// Text to Speech
          internal static let title = ScreenshotL10n.tr("Localizable", "settings.task.tts.title", fallback: "Text to Speech")
        }
        internal enum UnresolvedBehavior {
          internal enum Option {
            /// Cancel
            internal static let cancel = ScreenshotL10n.tr("Localizable", "settings.task.unresolved_behavior.option.cancel", fallback: "Cancel")
            /// Ask before sending
            internal static let confirm = ScreenshotL10n.tr("Localizable", "settings.task.unresolved_behavior.option.confirm", fallback: "Ask before sending")
            /// Use default target
            internal static let `default` = ScreenshotL10n.tr("Localizable", "settings.task.unresolved_behavior.option.default", fallback: "Use default target")
            /// Let model decide
            internal static let model = ScreenshotL10n.tr("Localizable", "settings.task.unresolved_behavior.option.model", fallback: "Let model decide")
          }
        }
        internal enum Update {
          /// Check for updates
          internal static let actionCheck = ScreenshotL10n.tr("Localizable", "settings.task.update.action_check", fallback: "Check for updates")
          /// Manage update checks.
          internal static let subtitle = ScreenshotL10n.tr("Localizable", "settings.task.update.subtitle", fallback: "Manage update checks.")
          /// Updates
          internal static let title = ScreenshotL10n.tr("Localizable", "settings.task.update.title", fallback: "Updates")
        }
        internal enum Workflow {
          internal enum ClipboardImage {
            /// Recognize text from images copied to the clipboard.
            internal static let subtitle = ScreenshotL10n.tr("Localizable", "settings.task.workflow.clipboard_image.subtitle", fallback: "Recognize text from images copied to the clipboard.")
            /// Clipboard Image OCR
            internal static let title = ScreenshotL10n.tr("Localizable", "settings.task.workflow.clipboard_image.title", fallback: "Clipboard Image OCR")
          }
          internal enum Group {
            /// Configure quick workflows and shortcuts.
            internal static let subtitle = ScreenshotL10n.tr("Localizable", "settings.task.workflow.group.subtitle", fallback: "Configure quick workflows and shortcuts.")
            /// Workflows
            internal static let title = ScreenshotL10n.tr("Localizable", "settings.task.workflow.group.title", fallback: "Workflows")
          }
          internal enum Palette {
            /// Open the palette for assets and commands.
            internal static let subtitle = ScreenshotL10n.tr("Localizable", "settings.task.workflow.palette.subtitle", fallback: "Open the palette for assets and commands.")
            /// Palette
            internal static let title = ScreenshotL10n.tr("Localizable", "settings.task.workflow.palette.title", fallback: "Palette")
          }
          internal enum Screenshot {
            /// Capture screenshots and extract text.
            internal static let subtitle = ScreenshotL10n.tr("Localizable", "settings.task.workflow.screenshot.subtitle", fallback: "Capture screenshots and extract text.")
            /// Screenshot OCR
            internal static let title = ScreenshotL10n.tr("Localizable", "settings.task.workflow.screenshot.title", fallback: "Screenshot OCR")
          }
        }
      }
      internal enum Window {
        /// VoxFlow Settings
        internal static let titleFormat = ScreenshotL10n.tr("Localizable", "settings.window.title_format", fallback: "VoxFlow Settings")
        internal enum Asr {
          /// Browse
          internal static let browse = ScreenshotL10n.tr("Localizable", "settings.window.asr.browse", fallback: "Browse")
          /// Choose a local ASR model folder.
          internal static let browseMessage = ScreenshotL10n.tr("Localizable", "settings.window.asr.browse_message", fallback: "Choose a local ASR model folder.")
          /// Choose
          internal static let browsePrompt = ScreenshotL10n.tr("Localizable", "settings.window.asr.browse_prompt", fallback: "Choose")
          /// Download model
          internal static let downloadModel = ScreenshotL10n.tr("Localizable", "settings.window.asr.download_model", fallback: "Download model")
          /// Engine
          internal static let engineLabel = ScreenshotL10n.tr("Localizable", "settings.window.asr.engine_label", fallback: "Engine")
          /// Model path
          internal static let modelPath = ScreenshotL10n.tr("Localizable", "settings.window.asr.model_path", fallback: "Model path")
          /// Choose a local model folder
          internal static let modelPathPlaceholder = ScreenshotL10n.tr("Localizable", "settings.window.asr.model_path_placeholder", fallback: "Choose a local model folder")
          /// Model size
          internal static let modelSize = ScreenshotL10n.tr("Localizable", "settings.window.asr.model_size", fallback: "Model size")
          /// Apple Speech
          internal static let systemSpeech = ScreenshotL10n.tr("Localizable", "settings.window.asr.system_speech", fallback: "Apple Speech")
          internal enum Status {
            /// Configured: %@
            internal static func configuredFormat(_ p1: Any) -> String {
              return ScreenshotL10n.tr("Localizable", "settings.window.asr.status.configured_format", String(describing: p1), fallback: "Configured: %@")
            }
            /// Download complete: %@
            internal static func downloadCompleteFormat(_ p1: Any) -> String {
              return ScreenshotL10n.tr("Localizable", "settings.window.asr.status.download_complete_format", String(describing: p1), fallback: "Download complete: %@")
            }
            /// Download failed: %@
            internal static func downloadFailedFormat(_ p1: Any) -> String {
              return ScreenshotL10n.tr("Localizable", "settings.window.asr.status.download_failed_format", String(describing: p1), fallback: "Download failed: %@")
            }
            /// Downloading: %@
            internal static func downloadingFormat(_ p1: Any) -> String {
              return ScreenshotL10n.tr("Localizable", "settings.window.asr.status.downloading_format", String(describing: p1), fallback: "Downloading: %@")
            }
            /// Incomplete: %@
            internal static func incompleteFormat(_ p1: Any) -> String {
              return ScreenshotL10n.tr("Localizable", "settings.window.asr.status.incomplete_format", String(describing: p1), fallback: "Incomplete: %@")
            }
            /// Not configured
            internal static let notConfigured = ScreenshotL10n.tr("Localizable", "settings.window.asr.status.not_configured", fallback: "Not configured")
            /// Preparing download: %@
            internal static func preparingDownloadFormat(_ p1: Any) -> String {
              return ScreenshotL10n.tr("Localizable", "settings.window.asr.status.preparing_download_format", String(describing: p1), fallback: "Preparing download: %@")
            }
          }
        }
        internal enum Keycode {
          /// Down Arrow
          internal static let downArrow = ScreenshotL10n.tr("Localizable", "settings.window.keycode.down_arrow", fallback: "Down Arrow")
          /// Left Arrow
          internal static let leftArrow = ScreenshotL10n.tr("Localizable", "settings.window.keycode.left_arrow", fallback: "Left Arrow")
          /// Left Command
          internal static let leftCommand = ScreenshotL10n.tr("Localizable", "settings.window.keycode.left_command", fallback: "Left Command")
          /// Left Control
          internal static let leftControl = ScreenshotL10n.tr("Localizable", "settings.window.keycode.left_control", fallback: "Left Control")
          /// Left Option
          internal static let leftOption = ScreenshotL10n.tr("Localizable", "settings.window.keycode.left_option", fallback: "Left Option")
          /// Left Shift
          internal static let leftShift = ScreenshotL10n.tr("Localizable", "settings.window.keycode.left_shift", fallback: "Left Shift")
          /// Right Arrow
          internal static let rightArrow = ScreenshotL10n.tr("Localizable", "settings.window.keycode.right_arrow", fallback: "Right Arrow")
          /// Right Command
          internal static let rightCommand = ScreenshotL10n.tr("Localizable", "settings.window.keycode.right_command", fallback: "Right Command")
          /// Right Control
          internal static let rightControl = ScreenshotL10n.tr("Localizable", "settings.window.keycode.right_control", fallback: "Right Control")
          /// Right Option
          internal static let rightOption = ScreenshotL10n.tr("Localizable", "settings.window.keycode.right_option", fallback: "Right Option")
          /// Right Shift
          internal static let rightShift = ScreenshotL10n.tr("Localizable", "settings.window.keycode.right_shift", fallback: "Right Shift")
          /// Unknown key: %@
          internal static func unknownFormat(_ p1: Any) -> String {
            return ScreenshotL10n.tr("Localizable", "settings.window.keycode.unknown_format", String(describing: p1), fallback: "Unknown key: %@")
          }
          /// Up Arrow
          internal static let upArrow = ScreenshotL10n.tr("Localizable", "settings.window.keycode.up_arrow", fallback: "Up Arrow")
        }
        internal enum Llm {
          /// API Key
          internal static let apiKey = ScreenshotL10n.tr("Localizable", "settings.window.llm.api_key", fallback: "API Key")
          /// Base URL
          internal static let baseUrl = ScreenshotL10n.tr("Localizable", "settings.window.llm.base_url", fallback: "Base URL")
          /// Model
          internal static let model = ScreenshotL10n.tr("Localizable", "settings.window.llm.model", fallback: "Model")
          internal enum Status {
            /// Failed to save API key: %@
            internal static func apiKeySaveFailedFormat(_ p1: Any) -> String {
              return ScreenshotL10n.tr("Localizable", "settings.window.llm.status.api_key_save_failed_format", String(describing: p1), fallback: "Failed to save API key: %@")
            }
            /// Connection failed: %@
            internal static func connectionFailedFormat(_ p1: Any) -> String {
              return ScreenshotL10n.tr("Localizable", "settings.window.llm.status.connection_failed_format", String(describing: p1), fallback: "Connection failed: %@")
            }
            /// Fill in all required fields.
            internal static let fillAllFields = ScreenshotL10n.tr("Localizable", "settings.window.llm.status.fill_all_fields", fallback: "Fill in all required fields.")
            /// Saved
            internal static let saved = ScreenshotL10n.tr("Localizable", "settings.window.llm.status.saved", fallback: "Saved")
            /// Testing
            internal static let testing = ScreenshotL10n.tr("Localizable", "settings.window.llm.status.testing", fallback: "Testing")
          }
        }
        internal enum Shortcut {
          /// Cancel
          internal static let cancel = ScreenshotL10n.tr("Localizable", "settings.window.shortcut.cancel", fallback: "Cancel")
          /// Current shortcut
          internal static let current = ScreenshotL10n.tr("Localizable", "settings.window.shortcut.current", fallback: "Current shortcut")
          /// Long-press threshold
          internal static let longPressThreshold = ScreenshotL10n.tr("Localizable", "settings.window.shortcut.long_press_threshold", fallback: "Long-press threshold")
          /// Record shortcut
          internal static let record = ScreenshotL10n.tr("Localizable", "settings.window.shortcut.record", fallback: "Record shortcut")
          /// Reset
          internal static let reset = ScreenshotL10n.tr("Localizable", "settings.window.shortcut.reset", fallback: "Reset")
          /// shortcut
          internal static let sheetLabel = ScreenshotL10n.tr("Localizable", "settings.window.shortcut.sheet_label", fallback: "shortcut")
          /// Short-press behavior
          internal static let shortPressBehavior = ScreenshotL10n.tr("Localizable", "settings.window.shortcut.short_press_behavior", fallback: "Short-press behavior")
          internal enum ShortPress {
            /// No short-press action
            internal static let `none` = ScreenshotL10n.tr("Localizable", "settings.window.shortcut.short_press.none", fallback: "No short-press action")
            /// Toggle listening
            internal static let toggleListening = ScreenshotL10n.tr("Localizable", "settings.window.shortcut.short_press.toggle_listening", fallback: "Toggle listening")
          }
        }
        internal enum Tab {
          /// ASR
          internal static let asr = ScreenshotL10n.tr("Localizable", "settings.window.tab.asr", fallback: "ASR")
          /// LLM
          internal static let llm = ScreenshotL10n.tr("Localizable", "settings.window.tab.llm", fallback: "LLM")
          /// Shortcut
          internal static let shortcut = ScreenshotL10n.tr("Localizable", "settings.window.tab.shortcut", fallback: "Shortcut")
        }
      }
      internal enum WorkflowName {
        /// Clipboard Image OCR
        internal static let clipboardImageOcr = ScreenshotL10n.tr("Localizable", "settings.workflow_name.clipboard_image_ocr", fallback: "Clipboard Image OCR")
        /// Palette
        internal static let palette = ScreenshotL10n.tr("Localizable", "settings.workflow_name.palette", fallback: "Palette")
        /// Screenshot OCR
        internal static let screenshotOcr = ScreenshotL10n.tr("Localizable", "settings.workflow_name.screenshot_ocr", fallback: "Screenshot OCR")
        /// Selection Action
        internal static let selectionAction = ScreenshotL10n.tr("Localizable", "settings.workflow_name.selection_action", fallback: "Selection Action")
        /// Selection Assistant
        internal static let selectionAgent = ScreenshotL10n.tr("Localizable", "settings.workflow_name.selection_agent", fallback: "Selection Assistant")
        /// Ask AI About Selection
        internal static let selectionAskAi = ScreenshotL10n.tr("Localizable", "settings.workflow_name.selection_ask_ai", fallback: "Ask AI About Selection")
        /// Summarize Selection
        internal static let selectionSummarize = ScreenshotL10n.tr("Localizable", "settings.workflow_name.selection_summarize", fallback: "Summarize Selection")
        /// Translate Selection
        internal static let selectionTranslate = ScreenshotL10n.tr("Localizable", "settings.workflow_name.selection_translate", fallback: "Translate Selection")
      }
    }
    internal enum Smart {
      internal enum Config {
        /// Applied: %@
        internal static func actionAppliedFormat(_ p1: Any) -> String {
          return ScreenshotL10n.tr("Localizable", "smart.config.action_applied_format", String(describing: p1), fallback: "Applied: %@")
        }
        /// Cancel
        internal static let actionCancel = ScreenshotL10n.tr("Localizable", "smart.config.action_cancel", fallback: "Cancel")
        /// %d apps
        internal static func appCountFormat(_ p1: Int) -> String {
          return ScreenshotL10n.tr("Localizable", "smart.config.app_count_format", p1, fallback: "%d apps")
        }
        /// Apply
        internal static let buttonApply = ScreenshotL10n.tr("Localizable", "smart.config.button_apply", fallback: "Apply")
        /// Cancel
        internal static let buttonCancel = ScreenshotL10n.tr("Localizable", "smart.config.button_cancel", fallback: "Cancel")
        /// Done
        internal static let buttonDone = ScreenshotL10n.tr("Localizable", "smart.config.button_done", fallback: "Done")
        /// Start scan
        internal static let buttonStartScan = ScreenshotL10n.tr("Localizable", "smart.config.button_start_scan", fallback: "Start scan")
        /// Close
        internal static let close = ScreenshotL10n.tr("Localizable", "smart.config.close", fallback: "Close")
        /// Smart configuration is ready.
        internal static let completedMessage = ScreenshotL10n.tr("Localizable", "smart.config.completed_message", fallback: "Smart configuration is ready.")
        /// Configuration complete
        internal static let completedTitle = ScreenshotL10n.tr("Localizable", "smart.config.completed_title", fallback: "Configuration complete")
        /// Found: %@
        internal static func discoveredFormat(_ p1: Any) -> String {
          return ScreenshotL10n.tr("Localizable", "smart.config.discovered_format", String(describing: p1), fallback: "Found: %@")
        }
        /// No installed apps matched a known preset yet. You can still let smart classification fill in the gaps or add your own rules.
        internal static let emptySubtitle = ScreenshotL10n.tr("Localizable", "smart.config.empty_subtitle", fallback: "No installed apps matched a known preset yet. You can still let smart classification fill in the gaps or add your own rules.")
        /// No known apps matched
        internal static let emptyTitle = ScreenshotL10n.tr("Localizable", "smart.config.empty_title", fallback: "No known apps matched")
        /// Configuration failed
        internal static let failedTitle = ScreenshotL10n.tr("Localizable", "smart.config.failed_title", fallback: "Configuration failed")
        /// Scan installed apps, recognize known apps, and add smart voice input recommendations.
        internal static let idleSubtitle = ScreenshotL10n.tr("Localizable", "smart.config.idle_subtitle", fallback: "Scan installed apps, recognize known apps, and add smart voice input recommendations.")
        /// Ready to scan apps
        internal static let idleTitle = ScreenshotL10n.tr("Localizable", "smart.config.idle_title", fallback: "Ready to scan apps")
        /// Applying recommendations...
        internal static let progressApplying = ScreenshotL10n.tr("Localizable", "smart.config.progress_applying", fallback: "Applying recommendations...")
        /// Classifying apps...
        internal static let progressClassifying = ScreenshotL10n.tr("Localizable", "smart.config.progress_classifying", fallback: "Classifying apps...")
        /// Scanning installed apps...
        internal static let progressScanning = ScreenshotL10n.tr("Localizable", "smart.config.progress_scanning", fallback: "Scanning installed apps...")
        /// AI recommendation
        internal static let sourceAiRecommendation = ScreenshotL10n.tr("Localizable", "smart.config.source_ai_recommendation", fallback: "AI recommendation")
        /// Default style
        internal static let sourceDefaultStyle = ScreenshotL10n.tr("Localizable", "smart.config.source_default_style", fallback: "Default style")
        /// Known app
        internal static let sourceSystemPreset = ScreenshotL10n.tr("Localizable", "smart.config.source_system_preset", fallback: "Known app")
        /// User rule
        internal static let sourceUserRule = ScreenshotL10n.tr("Localizable", "smart.config.source_user_rule", fallback: "User rule")
        /// Scan installed apps and recommend a voice input style for each one.
        internal static let subtitle = ScreenshotL10n.tr("Localizable", "smart.config.subtitle", fallback: "Scan installed apps and recommend a voice input style for each one.")
        /// App Style Recommendations
        internal static let title = ScreenshotL10n.tr("Localizable", "smart.config.title", fallback: "App Style Recommendations")
      }
    }
    internal enum Style {
      internal enum Action {
        /// Confirm
        internal static let confirm = ScreenshotL10n.tr("Localizable", "style.action.confirm", fallback: "Confirm")
        /// Done
        internal static let done = ScreenshotL10n.tr("Localizable", "style.action.done", fallback: "Done")
        /// Manage apps
        internal static let manageApps = ScreenshotL10n.tr("Localizable", "style.action.manage_apps", fallback: "Manage apps")
        /// Restore default
        internal static let restoreDefault = ScreenshotL10n.tr("Localizable", "style.action.restore_default", fallback: "Restore default")
        /// Smart configuration
        internal static let smartConfiguration = ScreenshotL10n.tr("Localizable", "style.action.smart_configuration", fallback: "Smart configuration")
      }
      internal enum AppRouting {
        /// No application bindings yet.
        internal static let noApplicationBindings = ScreenshotL10n.tr("Localizable", "style.app_routing.no_application_bindings", fallback: "No application bindings yet.")
        /// Rescan apps
        internal static let rescan = ScreenshotL10n.tr("Localizable", "style.app_routing.rescan", fallback: "Rescan apps")
        /// Select apps for this style.
        internal static let selectAppForStyle = ScreenshotL10n.tr("Localizable", "style.app_routing.select_app_for_style", fallback: "Select apps for this style.")
        /// App routing
        internal static let title = ScreenshotL10n.tr("Localizable", "style.app_routing.title", fallback: "App routing")
      }
      internal enum Error {
        /// Choose an app first.
        internal static let applicationIdentityRequired = ScreenshotL10n.tr("Localizable", "style.error.application_identity_required", fallback: "Choose an app first.")
        /// Style not found.
        internal static let notFound = ScreenshotL10n.tr("Localizable", "style.error.not_found", fallback: "Style not found.")
        /// Prompt cannot be empty.
        internal static let promptRequired = ScreenshotL10n.tr("Localizable", "style.error.prompt_required", fallback: "Prompt cannot be empty.")
      }
      internal enum Feedback {
        /// App rule deleted
        internal static let appRuleDeleted = ScreenshotL10n.tr("Localizable", "style.feedback.app_rule_deleted", fallback: "App rule deleted")
        /// App rule saved
        internal static let appRuleSaved = ScreenshotL10n.tr("Localizable", "style.feedback.app_rule_saved", fallback: "App rule saved")
        /// Prompt reset
        internal static let resetPrompt = ScreenshotL10n.tr("Localizable", "style.feedback.reset_prompt", fallback: "Prompt reset")
        /// Style saved
        internal static let saved = ScreenshotL10n.tr("Localizable", "style.feedback.saved", fallback: "Style saved")
        /// Default style set
        internal static let setDefault = ScreenshotL10n.tr("Localizable", "style.feedback.set_default", fallback: "Default style set")
      }
      internal enum Profile {
        internal enum Casual {
          /// Built-in
          internal static let category = ScreenshotL10n.tr("Localizable", "style.profile.casual.category", fallback: "Built-in")
          /// Casual
          internal static let name = ScreenshotL10n.tr("Localizable", "style.profile.casual.name", fallback: "Casual")
          /// Natural conversational tone
          internal static let subtitle = ScreenshotL10n.tr("Localizable", "style.profile.casual.subtitle", fallback: "Natural conversational tone")
        }
        internal enum Chat {
          /// Built-in
          internal static let category = ScreenshotL10n.tr("Localizable", "style.profile.chat.category", fallback: "Built-in")
          /// Chat
          internal static let name = ScreenshotL10n.tr("Localizable", "style.profile.chat.name", fallback: "Chat")
          /// For instant messages and chat
          internal static let subtitle = ScreenshotL10n.tr("Localizable", "style.profile.chat.subtitle", fallback: "For instant messages and chat")
        }
        internal enum Coding {
          /// Built-in
          internal static let category = ScreenshotL10n.tr("Localizable", "style.profile.coding.category", fallback: "Built-in")
          /// Coding
          internal static let name = ScreenshotL10n.tr("Localizable", "style.profile.coding.name", fallback: "Coding")
          /// Prioritize technical terms
          internal static let subtitle = ScreenshotL10n.tr("Localizable", "style.profile.coding.subtitle", fallback: "Prioritize technical terms")
        }
        internal enum Email {
          /// Built-in
          internal static let category = ScreenshotL10n.tr("Localizable", "style.profile.email.category", fallback: "Built-in")
          /// Email
          internal static let name = ScreenshotL10n.tr("Localizable", "style.profile.email.name", fallback: "Email")
          /// For email and messages
          internal static let subtitle = ScreenshotL10n.tr("Localizable", "style.profile.email.subtitle", fallback: "For email and messages")
        }
        internal enum Energetic {
          /// Built-in
          internal static let category = ScreenshotL10n.tr("Localizable", "style.profile.energetic.category", fallback: "Built-in")
          /// Energetic
          internal static let name = ScreenshotL10n.tr("Localizable", "style.profile.energetic.name", fallback: "Energetic")
          /// Livelier without overdoing it
          internal static let subtitle = ScreenshotL10n.tr("Localizable", "style.profile.energetic.subtitle", fallback: "Livelier without overdoing it")
        }
        internal enum Formal {
          /// Built-in
          internal static let category = ScreenshotL10n.tr("Localizable", "style.profile.formal.category", fallback: "Built-in")
          /// Formal
          internal static let name = ScreenshotL10n.tr("Localizable", "style.profile.formal.name", fallback: "Formal")
          /// Better for reports and documents
          internal static let subtitle = ScreenshotL10n.tr("Localizable", "style.profile.formal.subtitle", fallback: "Better for reports and documents")
        }
        internal enum Original {
          /// Built-in
          internal static let category = ScreenshotL10n.tr("Localizable", "style.profile.original.category", fallback: "Built-in")
          /// Original
          internal static let name = ScreenshotL10n.tr("Localizable", "style.profile.original.name", fallback: "Original")
          /// Keep the original wording
          internal static let subtitle = ScreenshotL10n.tr("Localizable", "style.profile.original.subtitle", fallback: "Keep the original wording")
        }
      }
      internal enum View {
        /// Preview
        internal static let preview = ScreenshotL10n.tr("Localizable", "style.view.preview", fallback: "Preview")
        /// Edit prompt
        internal static let promptEditorHint = ScreenshotL10n.tr("Localizable", "style.view.prompt_editor_hint", fallback: "Edit prompt")
        /// Styles
        internal static let title = ScreenshotL10n.tr("Localizable", "style.view.title", fallback: "Styles")
      }
    }
    internal enum Subtitle {
      internal enum Editor {
        /// Burn subtitles
        internal static let actionBurn = ScreenshotL10n.tr("Localizable", "subtitle.editor.action_burn", fallback: "Burn subtitles")
        /// Cancel
        internal static let actionCancel = ScreenshotL10n.tr("Localizable", "subtitle.editor.action_cancel", fallback: "Cancel")
        /// Close editor
        internal static let actionClose = ScreenshotL10n.tr("Localizable", "subtitle.editor.action_close", fallback: "Close editor")
        /// Delete segment
        internal static let actionDeleteSegmentHelp = ScreenshotL10n.tr("Localizable", "subtitle.editor.action_delete_segment_help", fallback: "Delete segment")
        /// Save draft
        internal static let actionSaveDraft = ScreenshotL10n.tr("Localizable", "subtitle.editor.action_save_draft", fallback: "Save draft")
        /// Burn failed
        internal static let alertBurnFailedTitle = ScreenshotL10n.tr("Localizable", "subtitle.editor.alert_burn_failed_title", fallback: "Burn failed")
        /// Cancel
        internal static let alertCancel = ScreenshotL10n.tr("Localizable", "subtitle.editor.alert_cancel", fallback: "Cancel")
        /// Confirm
        internal static let alertConfirm = ScreenshotL10n.tr("Localizable", "subtitle.editor.alert_confirm", fallback: "Confirm")
        /// Generate
        internal static let alertGenerateConfirm = ScreenshotL10n.tr("Localizable", "subtitle.editor.alert_generate_confirm", fallback: "Generate")
        /// Generate subtitles for this recording now?
        internal static let alertGenerateMessage = ScreenshotL10n.tr("Localizable", "subtitle.editor.alert_generate_message", fallback: "Generate subtitles for this recording now?")
        /// Generate subtitles
        internal static let alertGenerateTitle = ScreenshotL10n.tr("Localizable", "subtitle.editor.alert_generate_title", fallback: "Generate subtitles")
        /// No subtitle segments
        internal static let emptySegments = ScreenshotL10n.tr("Localizable", "subtitle.editor.empty_segments", fallback: "No subtitle segments")
        /// Failed to load subtitle draft.
        internal static let errorDraftLoadFailed = ScreenshotL10n.tr("Localizable", "subtitle.editor.error_draft_load_failed", fallback: "Failed to load subtitle draft.")
        /// Draft saved
        internal static let feedbackDraftSaved = ScreenshotL10n.tr("Localizable", "subtitle.editor.feedback_draft_saved", fallback: "Draft saved")
        /// Failed to save draft.
        internal static let feedbackSaveFailed = ScreenshotL10n.tr("Localizable", "subtitle.editor.feedback_save_failed", fallback: "Failed to save draft.")
        /// %d segments
        internal static func segmentCountFormat(_ p1: Int) -> String {
          return ScreenshotL10n.tr("Localizable", "subtitle.editor.segment_count_format", p1, fallback: "%d segments")
        }
        /// Segments
        internal static let segmentListTitle = ScreenshotL10n.tr("Localizable", "subtitle.editor.segment_list_title", fallback: "Segments")
        /// Subtitle style: %@
        internal static func styleSummaryFormat(_ p1: Any) -> String {
          return ScreenshotL10n.tr("Localizable", "subtitle.editor.style_summary_format", String(describing: p1), fallback: "Subtitle style: %@")
        }
        /// Add subtitles
        internal static let titleAdd = ScreenshotL10n.tr("Localizable", "subtitle.editor.title_add", fallback: "Add subtitles")
      }
      internal enum Error {
        /// Failed to extract audio: %@
        internal static func audioExtractionFailedFormat(_ p1: Any) -> String {
          return ScreenshotL10n.tr("Localizable", "subtitle.error.audio_extraction_failed_format", String(describing: p1), fallback: "Failed to extract audio: %@")
        }
        /// Failed to burn subtitles: %@
        internal static func burnFailedFormat(_ p1: Any) -> String {
          return ScreenshotL10n.tr("Localizable", "subtitle.error.burn_failed_format", String(describing: p1), fallback: "Failed to burn subtitles: %@")
        }
        /// Burned subtitle output is missing.
        internal static let burnOutputMissing = ScreenshotL10n.tr("Localizable", "subtitle.error.burn_output_missing", fallback: "Burned subtitle output is missing.")
        /// Subtitle draft is missing.
        internal static let draftMissing = ScreenshotL10n.tr("Localizable", "subtitle.error.draft_missing", fallback: "Subtitle draft is missing.")
        /// Could not create the export session.
        internal static let exportSessionCreateFailed = ScreenshotL10n.tr("Localizable", "subtitle.error.export_session_create_failed", fallback: "Could not create the export session.")
        /// Could not export the subtitled video: %@
        internal static func exportSubtitledVideoFailedFormat(_ p1: Any) -> String {
          return ScreenshotL10n.tr("Localizable", "subtitle.error.export_subtitled_video_failed_format", String(describing: p1), fallback: "Could not export the subtitled video: %@")
        }
        /// Extracted audio is missing.
        internal static let extractedAudioMissing = ScreenshotL10n.tr("Localizable", "subtitle.error.extracted_audio_missing", fallback: "Extracted audio is missing.")
        /// Invalid subtitle source: %@
        internal static func invalidSourceFormat(_ p1: Any) -> String {
          return ScreenshotL10n.tr("Localizable", "subtitle.error.invalid_source_format", String(describing: p1), fallback: "Invalid subtitle source: %@")
        }
        /// The selected subtitle language is unavailable.
        internal static let languageNotAvailable = ScreenshotL10n.tr("Localizable", "subtitle.error.language_not_available", fallback: "The selected subtitle language is unavailable.")
        /// Video track is missing.
        internal static let missingVideoTrack = ScreenshotL10n.tr("Localizable", "subtitle.error.missing_video_track", fallback: "Video track is missing.")
        /// This recording has no microphone audio, so subtitles cannot be added
        internal static let noMicrophoneTrack = ScreenshotL10n.tr("Localizable", "subtitle.error.no_microphone_track", fallback: "This recording has no microphone audio, so subtitles cannot be added")
        /// Speech recognition permission is required.
        internal static let recognitionPermissionRequired = ScreenshotL10n.tr("Localizable", "subtitle.error.recognition_permission_required", fallback: "Speech recognition permission is required.")
        /// Speech recognition is unavailable.
        internal static let recognitionUnavailable = ScreenshotL10n.tr("Localizable", "subtitle.error.recognition_unavailable", fallback: "Speech recognition is unavailable.")
        /// Recording video is missing.
        internal static let recordingVideoMissing = ScreenshotL10n.tr("Localizable", "subtitle.error.recording_video_missing", fallback: "Recording video is missing.")
        /// Subtitle generation failed: %@
        internal static func subtitleGenerationFailedFormat(_ p1: Any) -> String {
          return ScreenshotL10n.tr("Localizable", "subtitle.error.subtitle_generation_failed_format", String(describing: p1), fallback: "Subtitle generation failed: %@")
        }
      }
      internal enum Hud {
        /// Add subtitles
        internal static let actionAddSubtitle = ScreenshotL10n.tr("Localizable", "subtitle.hud.action_add_subtitle", fallback: "Add subtitles")
        /// View/Edit subtitles
        internal static let actionEditSubtitle = ScreenshotL10n.tr("Localizable", "subtitle.hud.action_edit_subtitle", fallback: "View/Edit subtitles")
        /// Open subtitled video
        internal static let actionOpenSubtitledVideo = ScreenshotL10n.tr("Localizable", "subtitle.hud.action_open_subtitled_video", fallback: "Open subtitled video")
        /// Regenerate subtitles
        internal static let actionRegenerateSubtitle = ScreenshotL10n.tr("Localizable", "subtitle.hud.action_regenerate_subtitle", fallback: "Regenerate subtitles")
        /// Burning subtitles...
        internal static let subtitleBurningHelp = ScreenshotL10n.tr("Localizable", "subtitle.hud.subtitle_burning_help", fallback: "Burning subtitles...")
        /// Generating subtitles...
        internal static let subtitleGeneratingHelp = ScreenshotL10n.tr("Localizable", "subtitle.hud.subtitle_generating_help", fallback: "Generating subtitles...")
      }
      internal enum Status {
        /// Burned
        internal static let burned = ScreenshotL10n.tr("Localizable", "subtitle.status.burned", fallback: "Burned")
        /// Burning
        internal static let burning = ScreenshotL10n.tr("Localizable", "subtitle.status.burning", fallback: "Burning")
        /// Draft ready
        internal static let draftReady = ScreenshotL10n.tr("Localizable", "subtitle.status.draft_ready", fallback: "Draft ready")
        /// Failed
        internal static let failed = ScreenshotL10n.tr("Localizable", "subtitle.status.failed", fallback: "Failed")
        /// Generating
        internal static let generating = ScreenshotL10n.tr("Localizable", "subtitle.status.generating", fallback: "Generating")
        /// Not added
        internal static let `none` = ScreenshotL10n.tr("Localizable", "subtitle.status.none", fallback: "Not added")
      }
      internal enum Style {
        /// Subtitle style
        internal static let summary = ScreenshotL10n.tr("Localizable", "subtitle.style.summary", fallback: "Subtitle style")
      }
    }
    internal enum Transcribe {
      /// File Transcription
      internal static let title = ScreenshotL10n.tr("Localizable", "transcribe.title", fallback: "File Transcription")
      internal enum Action {
        /// ===== Transcribe =====
        internal static let cancel = ScreenshotL10n.tr("Localizable", "transcribe.action.cancel", fallback: "Cancel")
        /// Cancel
        internal static let cancelJob = ScreenshotL10n.tr("Localizable", "transcribe.action.cancel_job", fallback: "Cancel")
        /// Copy
        internal static let copy = ScreenshotL10n.tr("Localizable", "transcribe.action.copy", fallback: "Copy")
        /// Delete
        internal static let delete = ScreenshotL10n.tr("Localizable", "transcribe.action.delete", fallback: "Delete")
        /// Delete
        internal static let deleteJob = ScreenshotL10n.tr("Localizable", "transcribe.action.delete_job", fallback: "Delete")
        /// Pause
        internal static let pause = ScreenshotL10n.tr("Localizable", "transcribe.action.pause", fallback: "Pause")
        /// Play
        internal static let play = ScreenshotL10n.tr("Localizable", "transcribe.action.play", fallback: "Play")
        /// Retry
        internal static let retry = ScreenshotL10n.tr("Localizable", "transcribe.action.retry", fallback: "Retry")
        /// Select File
        internal static let selectFile = ScreenshotL10n.tr("Localizable", "transcribe.action.select_file", fallback: "Select File")
        /// Start
        internal static let start = ScreenshotL10n.tr("Localizable", "transcribe.action.start", fallback: "Start")
      }
      internal enum Delete {
        /// This transcription job will be removed.
        internal static let confirmMessage = ScreenshotL10n.tr("Localizable", "transcribe.delete.confirm_message", fallback: "This transcription job will be removed.")
        /// Delete Transcription Job
        internal static let confirmTitle = ScreenshotL10n.tr("Localizable", "transcribe.delete.confirm_title", fallback: "Delete Transcription Job")
      }
      internal enum DropArea {
        /// Drag and drop audio files here.
        internal static let placeholder = ScreenshotL10n.tr("Localizable", "transcribe.drop_area.placeholder", fallback: "Drag and drop audio files here.")
      }
      internal enum Error {
        /// Final transcription timed out.
        internal static let finalTimeout = ScreenshotL10n.tr("Localizable", "transcribe.error.final_timeout", fallback: "Final transcription timed out.")
        /// Transcription was interrupted.
        internal static let interrupted = ScreenshotL10n.tr("Localizable", "transcribe.error.interrupted", fallback: "Transcription was interrupted.")
        /// Unable to read the audio buffer.
        internal static let invalidAudioBuffer = ScreenshotL10n.tr("Localizable", "transcribe.error.invalid_audio_buffer", fallback: "Unable to read the audio buffer.")
        /// Transcription result is unavailable.
        internal static let resultUnavailable = ScreenshotL10n.tr("Localizable", "transcribe.error.result_unavailable", fallback: "Transcription result is unavailable.")
        /// Unsupported file format: %@.
        internal static func unsupportedFormat(_ p1: Any) -> String {
          return ScreenshotL10n.tr("Localizable", "transcribe.error.unsupported_format", String(describing: p1), fallback: "Unsupported file format: %@.")
        }
        /// Unsupported recognition language: %@.
        internal static func unsupportedLanguage(_ p1: Any) -> String {
          return ScreenshotL10n.tr("Localizable", "transcribe.error.unsupported_language", String(describing: p1), fallback: "Unsupported recognition language: %@.")
        }
      }
      internal enum Feedback {
        /// Transcription completed.
        internal static let completed = ScreenshotL10n.tr("Localizable", "transcribe.feedback.completed", fallback: "Transcription completed.")
        /// Transcription copied.
        internal static let copied = ScreenshotL10n.tr("Localizable", "transcribe.feedback.copied", fallback: "Transcription copied.")
        /// Transcription job deleted.
        internal static let deleted = ScreenshotL10n.tr("Localizable", "transcribe.feedback.deleted", fallback: "Transcription job deleted.")
        /// Exported as %@.
        internal static func exportedFormat(_ p1: Any) -> String {
          return ScreenshotL10n.tr("Localizable", "transcribe.feedback.exported_format", String(describing: p1), fallback: "Exported as %@.")
        }
        /// %d transcription jobs added.
        internal static func jobsAdded(_ p1: Int) -> String {
          return ScreenshotL10n.tr("Localizable", "transcribe.feedback.jobs_added", p1, fallback: "%d transcription jobs added.")
        }
        /// Saved transcription as note.
        internal static let savedAsNote = ScreenshotL10n.tr("Localizable", "transcribe.feedback.saved_as_note", fallback: "Saved transcription as note.")
      }
      internal enum Header {
        /// Import audio and transcribe to text.
        internal static let subtitle = ScreenshotL10n.tr("Localizable", "transcribe.header.subtitle", fallback: "Import audio and transcribe to text.")
      }
      internal enum Status {
        /// Cancelled
        internal static let cancelled = ScreenshotL10n.tr("Localizable", "transcribe.status.cancelled", fallback: "Cancelled")
        /// Completed
        internal static let completed = ScreenshotL10n.tr("Localizable", "transcribe.status.completed", fallback: "Completed")
        /// Failed
        internal static let failed = ScreenshotL10n.tr("Localizable", "transcribe.status.failed", fallback: "Failed")
        /// Running
        internal static let running = ScreenshotL10n.tr("Localizable", "transcribe.status.running", fallback: "Running")
        /// Waiting
        internal static let waiting = ScreenshotL10n.tr("Localizable", "transcribe.status.waiting", fallback: "Waiting")
      }
    }
    internal enum Transcription {
      internal enum Detail {
        /// ASR
        internal static let asrSection = ScreenshotL10n.tr("Localizable", "transcription.detail.asr_section", fallback: "ASR")
        /// Processing chain (transcription detail)
        internal static let finalText = ScreenshotL10n.tr("Localizable", "transcription.detail.final_text", fallback: "Final Text")
        /// Go to Auto-learning
        internal static let goToLearning = ScreenshotL10n.tr("Localizable", "transcription.detail.go_to_learning", fallback: "Go to Auto-learning")
        /// Hotword candidates
        internal static let hotwordCandidates = ScreenshotL10n.tr("Localizable", "transcription.detail.hotword_candidates", fallback: "Hotword candidates")
        /// delivered
        internal static let hotwordDelivered = ScreenshotL10n.tr("Localizable", "transcription.detail.hotword_delivered", fallback: "delivered")
        /// pruned
        internal static let hotwordPruned = ScreenshotL10n.tr("Localizable", "transcription.detail.hotword_pruned", fallback: "pruned")
        /// Unsupported reason
        internal static let hotwordUnsupportedReason = ScreenshotL10n.tr("Localizable", "transcription.detail.hotword_unsupported_reason", fallback: "Unsupported reason")
        /// LLM Correction
        internal static let llmSection = ScreenshotL10n.tr("Localizable", "transcription.detail.llm_section", fallback: "LLM Correction")
        /// OCR Temporary Context
        internal static let ocrSection = ScreenshotL10n.tr("Localizable", "transcription.detail.ocr_section", fallback: "OCR Temporary Context")
        /// This session only, not learned
        internal static let ocrTemporaryHint = ScreenshotL10n.tr("Localizable", "transcription.detail.ocr_temporary_hint", fallback: "This session only, not learned")
        /// This session
        internal static let ocrValidity = ScreenshotL10n.tr("Localizable", "transcription.detail.ocr_validity", fallback: "This session")
        /// Raw Transcript
        internal static let originalText = ScreenshotL10n.tr("Localizable", "transcription.detail.original_text", fallback: "Raw Transcript")
        /// Processing Chain
        internal static let processingChain = ScreenshotL10n.tr("Localizable", "transcription.detail.processing_chain", fallback: "Processing Chain")
        /// Checked, no match
        internal static let textReplacementChecked = ScreenshotL10n.tr("Localizable", "transcription.detail.text_replacement_checked", fallback: "Checked, no match")
        /// After LLM, before output
        internal static let textReplacementPosition = ScreenshotL10n.tr("Localizable", "transcription.detail.text_replacement_position", fallback: "After LLM, before output")
        /// Text Replacement
        internal static let textReplacementSection = ScreenshotL10n.tr("Localizable", "transcription.detail.text_replacement_section", fallback: "Text Replacement")
      }
    }
    internal enum Translation {
      internal enum Error {
        /// Translation was cancelled.
        internal static let cancelled = ScreenshotL10n.tr("Localizable", "translation.error.cancelled", fallback: "Translation was cancelled.")
        /// System translation failed internally.
        internal static let internalFailure = ScreenshotL10n.tr("Localizable", "translation.error.internal_failure", fallback: "System translation failed internally.")
        /// System language pack download failed.
        internal static let languagePackDownloadFailed = ScreenshotL10n.tr("Localizable", "translation.error.language_pack_download_failed", fallback: "System language pack download failed.")
        /// Translation session host is unavailable.
        internal static let sessionHostUnavailable = ScreenshotL10n.tr("Localizable", "translation.error.session_host_unavailable", fallback: "Translation session host is unavailable.")
        /// Unable to identify source language.
        internal static let unableToIdentifyLanguage = ScreenshotL10n.tr("Localizable", "translation.error.unable_to_identify_language", fallback: "Unable to identify source language.")
        /// ===== Translation =====
        internal static let unavailableOnCurrentSystem = ScreenshotL10n.tr("Localizable", "translation.error.unavailable_on_current_system", fallback: "Apple translation is unavailable on this system.")
        /// The source language is not supported by system translation.
        internal static let unsupportedLanguage = ScreenshotL10n.tr("Localizable", "translation.error.unsupported_language", fallback: "The source language is not supported by system translation.")
      }
    }
    internal enum Updates {
      internal enum Prompt {
        /// ===== Updates =====
        internal static let availableTitle = ScreenshotL10n.tr("Localizable", "updates.prompt.available_title", fallback: "New update available for VoxFlow")
        /// Close
        internal static let closeAccessibility = ScreenshotL10n.tr("Localizable", "updates.prompt.close_accessibility", fallback: "Close")
        /// Close and remind me later
        internal static let closeHelp = ScreenshotL10n.tr("Localizable", "updates.prompt.close_help", fallback: "Close and remind me later")
        /// Current version:
        internal static let currentVersionPrefix = ScreenshotL10n.tr("Localizable", "updates.prompt.current_version_prefix", fallback: "Current version:")
        /// Unable to retrieve latest release right now, please try again later.
        internal static let failureMessage = ScreenshotL10n.tr("Localizable", "updates.prompt.failure_message", fallback: "Unable to retrieve latest release right now, please try again later.")
        /// Update Check Failed
        internal static let failureTitle = ScreenshotL10n.tr("Localizable", "updates.prompt.failure_title", fallback: "Update Check Failed")
        /// Latest version:
        internal static let latestVersionPrefix = ScreenshotL10n.tr("Localizable", "updates.prompt.latest_version_prefix", fallback: "Latest version:")
        /// Open the release page to see all details.
        internal static let noSummaryFallback = ScreenshotL10n.tr("Localizable", "updates.prompt.no_summary_fallback", fallback: "Open the release page to see all details.")
        /// VoxFlow is already the latest stable version.
        internal static let upToDateMessage = ScreenshotL10n.tr("Localizable", "updates.prompt.up_to_date_message", fallback: "VoxFlow is already the latest stable version.")
        /// Current version is up to date
        internal static let upToDateTitle = ScreenshotL10n.tr("Localizable", "updates.prompt.up_to_date_title", fallback: "Current version is up to date")
        /// VoxFlow Update
        internal static let windowTitle = ScreenshotL10n.tr("Localizable", "updates.prompt.window_title", fallback: "VoxFlow Update")
        internal enum Action {
          /// Download Update
          internal static let download = ScreenshotL10n.tr("Localizable", "updates.prompt.action.download", fallback: "Download Update")
          /// Skip This Version
          internal static let ignore = ScreenshotL10n.tr("Localizable", "updates.prompt.action.ignore", fallback: "Skip This Version")
          /// OK
          internal static let ok = ScreenshotL10n.tr("Localizable", "updates.prompt.action.ok", fallback: "OK")
          /// Remind Tomorrow
          internal static let remindTomorrow = ScreenshotL10n.tr("Localizable", "updates.prompt.action.remind_tomorrow", fallback: "Remind Tomorrow")
        }
      }
    }
    internal enum Vibe {
      internal enum Agent {
        /// %d associated logs
        internal static func associatedRefsFormat(_ p1: Int) -> String {
          return ScreenshotL10n.tr("Localizable", "vibe.agent.associated_refs_format", p1, fallback: "%d associated logs")
        }
        /// Copy launch command
        internal static let copyLaunchCommand = ScreenshotL10n.tr("Localizable", "vibe.agent.copy_launch_command", fallback: "Copy launch command")
        /// Show MCP logs
        internal static let showMcpLogs = ScreenshotL10n.tr("Localizable", "vibe.agent.show_mcp_logs", fallback: "Show MCP logs")
        /// Stop process
        internal static let stopProcess = ScreenshotL10n.tr("Localizable", "vibe.agent.stop_process", fallback: "Stop process")
      }
      internal enum Alias {
        /// Cancel
        internal static let cancel = ScreenshotL10n.tr("Localizable", "vibe.alias.cancel", fallback: "Cancel")
        /// Save alias
        internal static let confirm = ScreenshotL10n.tr("Localizable", "vibe.alias.confirm", fallback: "Save alias")
        /// Edit alias
        internal static let edit = ScreenshotL10n.tr("Localizable", "vibe.alias.edit", fallback: "Edit alias")
        /// Alias
        internal static let fieldTitle = ScreenshotL10n.tr("Localizable", "vibe.alias.field_title", fallback: "Alias")
      }
      internal enum CurrentAgents {
        /// Clean stale sessions
        internal static let cleanStale = ScreenshotL10n.tr("Localizable", "vibe.current_agents.clean_stale", fallback: "Clean stale sessions")
        /// No active task assistants
        internal static let empty = ScreenshotL10n.tr("Localizable", "vibe.current_agents.empty", fallback: "No active task assistants")
        /// %d inactive sessions hidden
        internal static func inactiveCountFormat(_ p1: Int) -> String {
          return ScreenshotL10n.tr("Localizable", "vibe.current_agents.inactive_count_format", p1, fallback: "%d inactive sessions hidden")
        }
        /// Refresh
        internal static let refresh = ScreenshotL10n.tr("Localizable", "vibe.current_agents.refresh", fallback: "Refresh")
        /// Live coding-agent sessions detected on this Mac.
        internal static let subtitle = ScreenshotL10n.tr("Localizable", "vibe.current_agents.subtitle", fallback: "Live coding-agent sessions detected on this Mac.")
        /// Current Assistants
        internal static let title = ScreenshotL10n.tr("Localizable", "vibe.current_agents.title", fallback: "Current Assistants")
      }
      internal enum Mcp {
        /// Config: %@
        internal static func configLine(_ p1: Any) -> String {
          return ScreenshotL10n.tr("Localizable", "vibe.mcp.config_line", String(describing: p1), fallback: "Config: %@")
        }
        /// Connected; waiting for activity
        internal static let connectedWaiting = ScreenshotL10n.tr("Localizable", "vibe.mcp.connected_waiting", fallback: "Connected; waiting for activity")
        /// Connected at %@
        internal static func connectedWithTime(_ p1: Any) -> String {
          return ScreenshotL10n.tr("Localizable", "vibe.mcp.connected_with_time", String(describing: p1), fallback: "Connected at %@")
        }
        /// MCP disabled
        internal static let disabled = ScreenshotL10n.tr("Localizable", "vibe.mcp.disabled", fallback: "MCP disabled")
        /// MCP disconnected
        internal static let disconnected = ScreenshotL10n.tr("Localizable", "vibe.mcp.disconnected", fallback: "MCP disconnected")
        /// MCP is connected but has not reported status yet.
        internal static let helpConnectedWithoutReport = ScreenshotL10n.tr("Localizable", "vibe.mcp.help_connected_without_report", fallback: "MCP is connected but has not reported status yet.")
        /// Enable MCP to inspect agent context and diagnostics.
        internal static let helpDisabled = ScreenshotL10n.tr("Localizable", "vibe.mcp.help_disabled", fallback: "Enable MCP to inspect agent context and diagnostics.")
        /// Context was injected, but the agent has not read it yet.
        internal static let helpInjectedWithoutReading = ScreenshotL10n.tr("Localizable", "vibe.mcp.help_injected_without_reading", fallback: "Context was injected, but the agent has not read it yet.")
        /// Start an MCP-enabled agent session to see live status.
        internal static let helpNotConnected = ScreenshotL10n.tr("Localizable", "vibe.mcp.help_not_connected", fallback: "Start an MCP-enabled agent session to see live status.")
        /// Last report: %@
        internal static func helpReportedFormat(_ p1: Any) -> String {
          return ScreenshotL10n.tr("Localizable", "vibe.mcp.help_reported_format", String(describing: p1), fallback: "Last report: %@")
        }
        /// Reported at %@
        internal static func reportedWithTime(_ p1: Any) -> String {
          return ScreenshotL10n.tr("Localizable", "vibe.mcp.reported_with_time", String(describing: p1), fallback: "Reported at %@")
        }
        /// Request: %@
        internal static func requestLine(_ p1: Any) -> String {
          return ScreenshotL10n.tr("Localizable", "vibe.mcp.request_line", String(describing: p1), fallback: "Request: %@")
        }
      }
      internal enum McpLog {
        /// Close
        internal static let close = ScreenshotL10n.tr("Localizable", "vibe.mcp_log.close", fallback: "Close")
        /// No MCP log content available
        internal static let contentMissing = ScreenshotL10n.tr("Localizable", "vibe.mcp_log.content_missing", fallback: "No MCP log content available")
        /// Log content
        internal static let contentTitle = ScreenshotL10n.tr("Localizable", "vibe.mcp_log.content_title", fallback: "Log content")
        /// Copy diagnostics
        internal static let copyDiagnostics = ScreenshotL10n.tr("Localizable", "vibe.mcp_log.copy_diagnostics", fallback: "Copy diagnostics")
        /// Arguments
        internal static let fieldArgs = ScreenshotL10n.tr("Localizable", "vibe.mcp_log.field_args", fallback: "Arguments")
        /// Command
        internal static let fieldCommand = ScreenshotL10n.tr("Localizable", "vibe.mcp_log.field_command", fallback: "Command")
        /// Configuration
        internal static let fieldConfig = ScreenshotL10n.tr("Localizable", "vibe.mcp_log.field_config", fallback: "Configuration")
        /// Last error
        internal static let fieldLastError = ScreenshotL10n.tr("Localizable", "vibe.mcp_log.field_last_error", fallback: "Last error")
        /// Last report
        internal static let fieldLastReport = ScreenshotL10n.tr("Localizable", "vibe.mcp_log.field_last_report", fallback: "Last report")
        /// Last request
        internal static let fieldLastRequest = ScreenshotL10n.tr("Localizable", "vibe.mcp_log.field_last_request", fallback: "Last request")
        /// Last seen
        internal static let fieldLastSeen = ScreenshotL10n.tr("Localizable", "vibe.mcp_log.field_last_seen", fallback: "Last seen")
        /// Log path
        internal static let fieldLogPath = ScreenshotL10n.tr("Localizable", "vibe.mcp_log.field_log_path", fallback: "Log path")
        /// Open log file
        internal static let openFile = ScreenshotL10n.tr("Localizable", "vibe.mcp_log.open_file", fallback: "Open log file")
        /// MCP log
        internal static let title = ScreenshotL10n.tr("Localizable", "vibe.mcp_log.title", fallback: "MCP log")
      }
      internal enum Page {
        /// AI Coding
        internal static let title = ScreenshotL10n.tr("Localizable", "vibe.page.title", fallback: "AI Coding")
      }
      internal enum RecentDispatches {
        /// Clear
        internal static let clear = ScreenshotL10n.tr("Localizable", "vibe.recent_dispatches.clear", fallback: "Clear")
        /// No dispatches yet
        internal static let empty = ScreenshotL10n.tr("Localizable", "vibe.recent_dispatches.empty", fallback: "No dispatches yet")
        /// Voice commands are stored locally on this Mac.
        internal static let localNotice = ScreenshotL10n.tr("Localizable", "vibe.recent_dispatches.local_notice", fallback: "Voice commands are stored locally on this Mac.")
        /// Not submitted yet
        internal static let notSubmitted = ScreenshotL10n.tr("Localizable", "vibe.recent_dispatches.not_submitted", fallback: "Not submitted yet")
        /// Sent
        internal static let submitted = ScreenshotL10n.tr("Localizable", "vibe.recent_dispatches.submitted", fallback: "Sent")
        /// Recent voice commands sent to coding agents.
        internal static let subtitle = ScreenshotL10n.tr("Localizable", "vibe.recent_dispatches.subtitle", fallback: "Recent voice commands sent to coding agents.")
        /// Dispatch History
        internal static let title = ScreenshotL10n.tr("Localizable", "vibe.recent_dispatches.title", fallback: "Dispatch History")
      }
      internal enum Time {
        /// %d days ago
        internal static func daysAgo(_ p1: Int) -> String {
          return ScreenshotL10n.tr("Localizable", "vibe.time.days_ago", p1, fallback: "%d days ago")
        }
        /// %d hours ago
        internal static func hoursAgo(_ p1: Int) -> String {
          return ScreenshotL10n.tr("Localizable", "vibe.time.hours_ago", p1, fallback: "%d hours ago")
        }
        /// Just now
        internal static let justNow = ScreenshotL10n.tr("Localizable", "vibe.time.just_now", fallback: "Just now")
        /// %d minutes ago
        internal static func minutesAgo(_ p1: Int) -> String {
          return ScreenshotL10n.tr("Localizable", "vibe.time.minutes_ago", p1, fallback: "%d minutes ago")
        }
      }
    }
    internal enum Vocabulary {
      internal enum Hotwords {
        /// Deleting will prevent auto-learning from re-adding this word.
        internal static let deleteConfirm = ScreenshotL10n.tr("Localizable", "vocabulary.hotwords.delete_confirm", fallback: "Deleting will prevent auto-learning from re-adding this word.")
        /// Maintain correct spellings only, used for ASR hotword boosting and LLM correction context.
        internal static let description = ScreenshotL10n.tr("Localizable", "vocabulary.hotwords.description", fallback: "Maintain correct spellings only, used for ASR hotword boosting and LLM correction context.")
        /// Type a hotword or edit hotwords.txt to add.
        internal static let emptyHint = ScreenshotL10n.tr("Localizable", "vocabulary.hotwords.empty_hint", fallback: "Type a hotword or edit hotwords.txt to add.")
        /// No hotwords yet
        internal static let emptyTitle = ScreenshotL10n.tr("Localizable", "vocabulary.hotwords.empty_title", fallback: "No hotwords yet")
        /// File
        internal static let fileButton = ScreenshotL10n.tr("Localizable", "vocabulary.hotwords.file_button", fallback: "File")
        /// Open hotwords.txt in the default editor
        internal static let fileButtonHelp = ScreenshotL10n.tr("Localizable", "vocabulary.hotwords.file_button_help", fallback: "Open hotwords.txt in the default editor")
        /// %d hits
        internal static func hitCountFormat(_ p1: Int) -> String {
          return ScreenshotL10n.tr("Localizable", "vocabulary.hotwords.hit_count_format", p1, fallback: "%d hits")
        }
        /// Type a hotword and press Enter
        internal static let inputPlaceholder = ScreenshotL10n.tr("Localizable", "vocabulary.hotwords.input_placeholder", fallback: "Type a hotword and press Enter")
        /// Press Enter to add
        internal static let inputReturnHint = ScreenshotL10n.tr("Localizable", "vocabulary.hotwords.input_return_hint", fallback: "Press Enter to add")
        /// Enabled: ASR Provider + LLM context · %d hotwords
        internal static func providerBudgetFormat(_ p1: Int) -> String {
          return ScreenshotL10n.tr("Localizable", "vocabulary.hotwords.provider_budget_format", p1, fallback: "Enabled: ASR Provider + LLM context · %d hotwords")
        }
        internal enum Toast {
          /// Hotword removed
          internal static let deleted = ScreenshotL10n.tr("Localizable", "vocabulary.hotwords.toast.deleted", fallback: "Hotword removed")
          /// Hotword already exists
          internal static let duplicate = ScreenshotL10n.tr("Localizable", "vocabulary.hotwords.toast.duplicate", fallback: "Hotword already exists")
          /// Synced from hotwords.txt
          internal static let synced = ScreenshotL10n.tr("Localizable", "vocabulary.hotwords.toast.synced", fallback: "Synced from hotwords.txt")
        }
      }
      internal enum Learning {
        /// Add
        internal static let accept = ScreenshotL10n.tr("Localizable", "vocabulary.learning.accept", fallback: "Add")
        /// Candidate hotwords found from LLM key_terms and history edits. Confirm to add them.
        internal static let drawerDescription = ScreenshotL10n.tr("Localizable", "vocabulary.learning.drawer_description", fallback: "Candidate hotwords found from LLM key_terms and history edits. Confirm to add them.")
        /// Auto-learning drawer
        internal static let drawerTitle = ScreenshotL10n.tr("Localizable", "vocabulary.learning.drawer_title", fallback: "Auto-learning Suggestions")
        /// No pending suggestions.
        internal static let empty = ScreenshotL10n.tr("Localizable", "vocabulary.learning.empty", fallback: "No pending suggestions.")
        /// Ignore
        internal static let ignore = ScreenshotL10n.tr("Localizable", "vocabulary.learning.ignore", fallback: "Ignore")
        /// Seen %d times
        internal static func observedCountFormat(_ p1: Int) -> String {
          return ScreenshotL10n.tr("Localizable", "vocabulary.learning.observed_count_format", p1, fallback: "Seen %d times")
        }
        internal enum Action {
          /// Add
          internal static let add = ScreenshotL10n.tr("Localizable", "vocabulary.learning.action.add", fallback: "Add")
          /// Collapse auto-learning suggestions
          internal static let collapse = ScreenshotL10n.tr("Localizable", "vocabulary.learning.action.collapse", fallback: "Collapse auto-learning suggestions")
          /// Expand auto-learning suggestions
          internal static let expand = ScreenshotL10n.tr("Localizable", "vocabulary.learning.action.expand", fallback: "Expand auto-learning suggestions")
          /// Ignore
          internal static let ignore = ScreenshotL10n.tr("Localizable", "vocabulary.learning.action.ignore", fallback: "Ignore")
        }
        internal enum Filter {
          /// All
          internal static let all = ScreenshotL10n.tr("Localizable", "vocabulary.learning.filter.all", fallback: "All")
          /// History
          internal static let history = ScreenshotL10n.tr("Localizable", "vocabulary.learning.filter.history", fallback: "History")
          /// LLM
          internal static let llm = ScreenshotL10n.tr("Localizable", "vocabulary.learning.filter.llm", fallback: "LLM")
          /// OCR
          internal static let ocr = ScreenshotL10n.tr("Localizable", "vocabulary.learning.filter.ocr", fallback: "OCR")
        }
        internal enum Toast {
          /// Added to hotwords
          internal static let accepted = ScreenshotL10n.tr("Localizable", "vocabulary.learning.toast.accepted", fallback: "Added to hotwords")
          /// Suggestion ignored
          internal static let ignored = ScreenshotL10n.tr("Localizable", "vocabulary.learning.toast.ignored", fallback: "Suggestion ignored")
        }
      }
      internal enum Tab {
        /// Vocabulary Center — Hotwords tab
        internal static let hotwords = ScreenshotL10n.tr("Localizable", "vocabulary.tab.hotwords", fallback: "Hotwords")
        /// Text Replacement
        internal static let textReplacement = ScreenshotL10n.tr("Localizable", "vocabulary.tab.text_replacement", fallback: "Text Replacement")
      }
      internal enum TextReplacement {
        /// Add
        internal static let add = ScreenshotL10n.tr("Localizable", "vocabulary.text_replacement.add", fallback: "Add")
        /// Add Snippet
        internal static let addSnippet = ScreenshotL10n.tr("Localizable", "vocabulary.text_replacement.add_snippet", fallback: "Add Snippet")
        /// Clear All
        internal static let clearAll = ScreenshotL10n.tr("Localizable", "vocabulary.text_replacement.clear_all", fallback: "Clear All")
        /// Vocabulary Center — Text Replacement tab
        internal static let description = ScreenshotL10n.tr("Localizable", "vocabulary.text_replacement.description", fallback: "Force-replace fixed text after recognition, runs after LLM and before output.")
        /// Add fixed spelling, abbreviation, or phrase replacements.
        internal static let emptyHint = ScreenshotL10n.tr("Localizable", "vocabulary.text_replacement.empty_hint", fallback: "Add fixed spelling, abbreviation, or phrase replacements.")
        /// No text replacements yet
        internal static let emptyTitle = ScreenshotL10n.tr("Localizable", "vocabulary.text_replacement.empty_title", fallback: "No text replacements yet")
        /// Rules run in saved order and take effect immediately.
        internal static let orderHint = ScreenshotL10n.tr("Localizable", "vocabulary.text_replacement.order_hint", fallback: "Rules run in saved order and take effect immediately.")
        /// Search replacement rules
        internal static let searchPlaceholder = ScreenshotL10n.tr("Localizable", "vocabulary.text_replacement.search_placeholder", fallback: "Search replacement rules")
        internal enum Modal {
          /// Cancel
          internal static let cancel = ScreenshotL10n.tr("Localizable", "vocabulary.text_replacement.modal.cancel", fallback: "Cancel")
          /// RegEx
          internal static let regex = ScreenshotL10n.tr("Localizable", "vocabulary.text_replacement.modal.regex", fallback: "RegEx")
          /// Replace with
          internal static let replacement = ScreenshotL10n.tr("Localizable", "vocabulary.text_replacement.modal.replacement", fallback: "Replace with")
          /// Save Changes
          internal static let save = ScreenshotL10n.tr("Localizable", "vocabulary.text_replacement.modal.save", fallback: "Save Changes")
          /// Add Snippet
          internal static let title = ScreenshotL10n.tr("Localizable", "vocabulary.text_replacement.modal.title", fallback: "Add Snippet")
          /// Trigger
          internal static let trigger = ScreenshotL10n.tr("Localizable", "vocabulary.text_replacement.modal.trigger", fallback: "Trigger")
          /// Matched word or phrase
          internal static let triggerPlaceholder = ScreenshotL10n.tr("Localizable", "vocabulary.text_replacement.modal.trigger_placeholder", fallback: "Matched word or phrase")
        }
      }
    }
    internal enum Window {
      internal enum Permission {
        /// ===== Window =====
        internal static let done = ScreenshotL10n.tr("Localizable", "window.permission.done", fallback: "Done")
        /// Open %@ Permission Settings
        internal static func openItemSettingsHelpFormat(_ p1: Any) -> String {
          return ScreenshotL10n.tr("Localizable", "window.permission.open_item_settings_help_format", String(describing: p1), fallback: "Open %@ Permission Settings")
        }
        /// Open System Settings
        internal static let openSystemSettings = ScreenshotL10n.tr("Localizable", "window.permission.open_system_settings", fallback: "Open System Settings")
        /// After changing permissions, please return to VoxFlow and recheck.
        internal static let returnToAppCheck = ScreenshotL10n.tr("Localizable", "window.permission.return_to_app_check", fallback: "After changing permissions, please return to VoxFlow and recheck.")
      }
    }
  }
  internal enum ScreenshotKit {
    internal enum Annotation {
      internal enum Font {
        /// Large
        internal static let large = ScreenshotL10n.tr("ScreenshotKit", "annotation.font.large", fallback: "Large")
        /// Medium
        internal static let medium = ScreenshotL10n.tr("ScreenshotKit", "annotation.font.medium", fallback: "Medium")
        /// Small
        internal static let small = ScreenshotL10n.tr("ScreenshotKit", "annotation.font.small", fallback: "Small")
      }
      internal enum Text {
        /// Text note
        internal static let placeholder = ScreenshotL10n.tr("ScreenshotKit", "annotation.text.placeholder", fallback: "Text note")
      }
    }
    internal enum Capture {
      internal enum Error {
        /// Screenshot cancelled
        internal static let cancelled = ScreenshotL10n.tr("ScreenshotKit", "capture.error.cancelled", fallback: "Screenshot cancelled")
        /// Unable to crop the selected area
        internal static let cropFailed = ScreenshotL10n.tr("ScreenshotKit", "capture.error.crop_failed", fallback: "Unable to crop the selected area")
        /// The current display is unavailable
        internal static let displayUnavailable = ScreenshotL10n.tr("ScreenshotKit", "capture.error.display_unavailable", fallback: "The current display is unavailable")
        /// Screenshot failed: %@
        internal static func failedFormat(_ p1: Any) -> String {
          return ScreenshotL10n.tr("ScreenshotKit", "capture.error.failed_format", String(describing: p1), fallback: "Screenshot failed: %@")
        }
        /// No display is available
        internal static let noActiveDisplay = ScreenshotL10n.tr("ScreenshotKit", "capture.error.no_active_display", fallback: "No display is available")
        /// Screen Recording permission is required
        internal static let permissionDenied = ScreenshotL10n.tr("ScreenshotKit", "capture.error.permission_denied", fallback: "Screen Recording permission is required")
        /// Screenshot cancelled
        internal static let selectionCancelled = ScreenshotL10n.tr("ScreenshotKit", "capture.error.selection_cancelled", fallback: "Screenshot cancelled")
        /// A screenshot flow is already in progress
        internal static let sessionInProgress = ScreenshotL10n.tr("ScreenshotKit", "capture.error.session_in_progress", fallback: "A screenshot flow is already in progress")
      }
    }
    internal enum Recording {
      internal enum Audio {
        /// Microphone
        internal static let microphone = ScreenshotL10n.tr("ScreenshotKit", "recording.audio.microphone", fallback: "Microphone")
        /// Microphone on
        internal static let microphoneOn = ScreenshotL10n.tr("ScreenshotKit", "recording.audio.microphone_on", fallback: "Microphone on")
        /// Silent
        internal static let `none` = ScreenshotL10n.tr("ScreenshotKit", "recording.audio.none", fallback: "Silent")
      }
      internal enum Button {
        /// Cancel
        internal static let cancel = ScreenshotL10n.tr("ScreenshotKit", "recording.button.cancel", fallback: "Cancel")
        /// Start
        internal static let start = ScreenshotL10n.tr("ScreenshotKit", "recording.button.start", fallback: "Start")
      }
      internal enum Eligibility {
        /// Area recording does not support multiple displays. Select an area on one screen.
        internal static let crossDisplay = ScreenshotL10n.tr("ScreenshotKit", "recording.eligibility.cross_display", fallback: "Area recording does not support multiple displays. Select an area on one screen.")
        /// The recording area is too small
        internal static let tooSmall = ScreenshotL10n.tr("ScreenshotKit", "recording.eligibility.too_small", fallback: "The recording area is too small")
      }
      internal enum Hud {
        /// Stop recording
        internal static let stop = ScreenshotL10n.tr("ScreenshotKit", "recording.hud.stop", fallback: "Stop recording")
        internal enum Accessibility {
          /// Recording screen
          internal static let recording = ScreenshotL10n.tr("ScreenshotKit", "recording.hud.accessibility.recording", fallback: "Recording screen")
        }
      }
      internal enum Preparation {
        /// Ready to record
        internal static let caption = ScreenshotL10n.tr("ScreenshotKit", "recording.preparation.caption", fallback: "Ready to record")
      }
    }
    internal enum Scrolling {
      internal enum Help {
        /// Accessibility permission is required for auto-scroll
        internal static let accessibilityRequired = ScreenshotL10n.tr("ScreenshotKit", "scrolling.help.accessibility_required", fallback: "Accessibility permission is required for auto-scroll")
        /// Auto-scroll
        internal static let autoScroll = ScreenshotL10n.tr("ScreenshotKit", "scrolling.help.auto_scroll", fallback: "Auto-scroll")
        /// Height limit reached
        internal static let heightLimit = ScreenshotL10n.tr("ScreenshotKit", "scrolling.help.height_limit", fallback: "Height limit reached")
        /// Pause auto-scroll
        internal static let pauseAutoScroll = ScreenshotL10n.tr("ScreenshotKit", "scrolling.help.pause_auto_scroll", fallback: "Pause auto-scroll")
        /// Paused because matching is unstable
        internal static let pausedUnstable = ScreenshotL10n.tr("ScreenshotKit", "scrolling.help.paused_unstable", fallback: "Paused because matching is unstable")
        /// Reached the end
        internal static let reachedEnd = ScreenshotL10n.tr("ScreenshotKit", "scrolling.help.reached_end", fallback: "Reached the end")
        /// Matching is unstable. You can keep scrolling.
        internal static let unstable = ScreenshotL10n.tr("ScreenshotKit", "scrolling.help.unstable", fallback: "Matching is unstable. You can keep scrolling.")
      }
    }
    internal enum Toolbar {
      /// Arrow
      internal static let arrow = ScreenshotL10n.tr("ScreenshotKit", "toolbar.arrow", fallback: "Arrow")
      /// Cancel
      internal static let cancel = ScreenshotL10n.tr("ScreenshotKit", "toolbar.cancel", fallback: "Cancel")
      /// Circle
      internal static let circle = ScreenshotL10n.tr("ScreenshotKit", "toolbar.circle", fallback: "Circle")
      /// Color
      internal static let color = ScreenshotL10n.tr("ScreenshotKit", "toolbar.color", fallback: "Color")
      /// Done
      internal static let complete = ScreenshotL10n.tr("ScreenshotKit", "toolbar.complete", fallback: "Done")
      /// Copy
      internal static let copy = ScreenshotL10n.tr("ScreenshotKit", "toolbar.copy", fallback: "Copy")
      /// Download
      internal static let download = ScreenshotL10n.tr("ScreenshotKit", "toolbar.download", fallback: "Download")
      /// Duplicate
      internal static let duplicate = ScreenshotL10n.tr("ScreenshotKit", "toolbar.duplicate", fallback: "Duplicate")
      /// Font size
      internal static let fontSize = ScreenshotL10n.tr("ScreenshotKit", "toolbar.font_size", fallback: "Font size")
      /// Line width
      internal static let lineWidth = ScreenshotL10n.tr("ScreenshotKit", "toolbar.line_width", fallback: "Line width")
      /// Mosaic
      internal static let mosaic = ScreenshotL10n.tr("ScreenshotKit", "toolbar.mosaic", fallback: "Mosaic")
      /// Numbered marker
      internal static let numberedMarker = ScreenshotL10n.tr("ScreenshotKit", "toolbar.numbered_marker", fallback: "Numbered marker")
      /// Paste
      internal static let paste = ScreenshotL10n.tr("ScreenshotKit", "toolbar.paste", fallback: "Paste")
      /// Pen
      internal static let pen = ScreenshotL10n.tr("ScreenshotKit", "toolbar.pen", fallback: "Pen")
      /// Point marker
      internal static let pointMarker = ScreenshotL10n.tr("ScreenshotKit", "toolbar.point_marker", fallback: "Point marker")
      /// Rectangle
      internal static let rectangle = ScreenshotL10n.tr("ScreenshotKit", "toolbar.rectangle", fallback: "Rectangle")
      /// Redo
      internal static let redo = ScreenshotL10n.tr("ScreenshotKit", "toolbar.redo", fallback: "Redo")
      /// Area recording
      internal static let screenRecording = ScreenshotL10n.tr("ScreenshotKit", "toolbar.screen_recording", fallback: "Area recording")
      /// Scrolling screenshot
      internal static let scrollCapture = ScreenshotL10n.tr("ScreenshotKit", "toolbar.scroll_capture", fallback: "Scrolling screenshot")
      /// Select
      internal static let select = ScreenshotL10n.tr("ScreenshotKit", "toolbar.select", fallback: "Select")
      /// Text
      internal static let text = ScreenshotL10n.tr("ScreenshotKit", "toolbar.text", fallback: "Text")
      /// Text recognition
      internal static let textRecognition = ScreenshotL10n.tr("ScreenshotKit", "toolbar.text_recognition", fallback: "Text recognition")
      /// Translate
      internal static let translate = ScreenshotL10n.tr("ScreenshotKit", "toolbar.translate", fallback: "Translate")
      /// T
      internal static let translationBadge = ScreenshotL10n.tr("ScreenshotKit", "toolbar.translation_badge", fallback: "T")
      /// Undo
      internal static let undo = ScreenshotL10n.tr("ScreenshotKit", "toolbar.undo", fallback: "Undo")
    }
    internal enum Translation {
      internal enum Error {
        /// Translation service is not ready
        internal static let notReady = ScreenshotL10n.tr("ScreenshotKit", "translation.error.not_ready", fallback: "Translation service is not ready")
      }
      internal enum Status {
        /// Translation failed
        internal static let failed = ScreenshotL10n.tr("ScreenshotKit", "translation.status.failed", fallback: "Translation failed")
        /// Translation failed: %@
        internal static func failedFormat(_ p1: Any) -> String {
          return ScreenshotL10n.tr("ScreenshotKit", "translation.status.failed_format", String(describing: p1), fallback: "Translation failed: %@")
        }
        /// Translating
        internal static let inProgress = ScreenshotL10n.tr("ScreenshotKit", "translation.status.in_progress", fallback: "Translating")
        /// Translating %d/%d
        internal static func progressFormat(_ p1: Int, _ p2: Int) -> String {
          return ScreenshotL10n.tr("ScreenshotKit", "translation.status.progress_format", p1, p2, fallback: "Translating %d/%d")
        }
      }
    }
  }
}
// swiftlint:enable explicit_type_interface function_parameter_count identifier_name line_length
// swiftlint:enable nesting type_body_length type_name vertical_whitespace_opening_braces

// MARK: - Implementation Details

extension ScreenshotL10n {
  private static func tr(_ table: String, _ key: String, _ args: CVarArg..., fallback value: String) -> String {
    let format = ScreenshotL10n.bundle.localizedString(forKey: key, value: value, table: table)
    return String(format: format, locale: ScreenshotL10n.locale, arguments: args)
  }
}
