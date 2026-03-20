import Foundation

enum AccessibilityID {
    // MARK: - Main Window / Content View
    static let mainSplitView = "mainSplitView"
    static let sidebar = "sidebar"
    static let sidebarHeader = "sidebarHeader"
    static let sidebarRecordsList = "sidebarRecordsList"
    static let newRecordingButton = "newRecordingButton"
    static let clearFilterButton = "clearFilterButton"
    static let emptyStateView = "emptyStateView"
    static let selectRecordPlaceholder = "selectRecordPlaceholder"

    // MARK: - Welcome / Empty Detail
    static let welcomeView = "welcomeView"
    static let welcomeStartRecordingButton = "welcomeStartRecordingButton"
    static let welcomeImportAudioButton = "welcomeImportAudioButton"
    static let welcomeSettingsLink = "welcomeSettingsLink"

    // MARK: - Record Row (sidebar)
    static let recordRow = "recordRow"
    static let recordRowName = "recordRowName"
    static let recordRowDate = "recordRowDate"
    static let recordRowDuration = "recordRowDuration"

    // MARK: - Record Detail View
    static let recordDetailView = "recordDetailView"
    static let recordTitle = "recordTitle"
    static let recordTitleEditField = "recordTitleEditField"

    // Player controls
    static let playPauseButton = "playPauseButton"
    static let skipBackwardButton = "skipBackwardButton"
    static let skipForwardButton = "skipForwardButton"
    static let playbackSpeedButton = "playbackSpeedButton"
    static let waveformScrubber = "waveformScrubber"
    static let currentTimeLabel = "currentTimeLabel"
    static let durationLabel = "durationLabel"

    // Tabs
    static let tabPicker = "tabPicker"
    static let transcriptionTab = "transcriptionTab"
    static let summaryTab = "summaryTab"

    // Transcription
    static let transcriptionEditor = "transcriptionEditor"
    static let transcriptionCopyButton = "transcriptionCopyButton"
    static let transcriptionModelPicker = "transcriptionModelPicker"
    static let transcribeButton = "transcribeButton"

    // Summary
    static let summaryView = "summaryView"
    static let summaryEditor = "summaryEditor"
    static let summaryCopyButton = "summaryCopyButton"
    static let summaryModelPicker = "summaryModelPicker"
    static let summarizeButton = "summarizeButton"

    // Tags
    static let tagInput = "tagInput"
    static let tagChip = "tagChip"
    static let tagsSection = "tagsSection"

    // Speakers
    static let speakersSection = "speakersSection"
    static let speakerTimeline = "speakerTimeline"
    static let speakerChip = "speakerChip"
    static let speakerManageButton = "speakerManageButton"
    static let speakerMergeSheet = "speakerMergeSheet"
    static let speakerMergeConfirmButton = "speakerMergeConfirmButton"
    static let speakerRenameFieldPrefix = "speakerRenameField_"

    // Actions
    static let actionBar = "actionBar"
    static let moreActionsMenu = "moreActionsMenu"
    static let moreActionsDownloadItem = "moreActionsDownloadItem"
    static let moreActionsRenameItem = "moreActionsRenameItem"
    static let moreActionsDeleteItem = "moreActionsDeleteItem"
    static let deleteButton = "deleteButton"
    static let deleteConfirmButton = "deleteConfirmButton"
    static let exportAudioButton = "exportAudioButton"

    // Processing
    static let processingProgress = "processingProgress"

    // MARK: - Recording Overlay
    static let recordingOverlay = "recordingOverlay"
    static let recordingTimer = "recordingTimer"
    static let recordingCloseButton = "recordingCloseButton"
    static let recordingStopButton = "recordingStopButton"
    static let recordingResumeButton = "recordingResumeButton"
    static let recordingSaveButton = "recordingSaveButton"

    // MARK: - Settings
    static let settingsView = "settingsView"
    static let settingsCloseButton = "settingsCloseButton"
    static let settingsTabPicker = "settingsTabPicker"
    static let settingsSpeechToTextTab = "settingsSpeechToTextTab"
    static let settingsSummaryTab = "settingsSummaryTab"
    static let settingsProviderPicker = "settingsProviderPicker"
    static let settingsLanguagePicker = "settingsLanguagePicker"
    static let settingsWhisperBaseURL = "settingsWhisperBaseURL"
    static let settingsWhisperAPIKey = "settingsWhisperAPIKey"
    static let settingsWhisperModel = "settingsWhisperModel"
    static let settingsOpenAIBaseURL = "settingsOpenAIBaseURL"
    static let settingsOpenAIAPIKey = "settingsOpenAIAPIKey"
    static let settingsOpenAIModel = "settingsOpenAIModel"
    static let settingsChunkPrompt = "settingsChunkPrompt"
    static let settingsSummaryPrompt = "settingsSummaryPrompt"
    static let settingsTitlePrompt = "settingsTitlePrompt"
    static let settingsChunkToggle = "settingsChunkToggle"
    static let settingsTitleToggle = "settingsTitleToggle"
    static let settingsChunkSize = "settingsChunkSize"

    // MARK: - Drag & Drop Overlay
    static let dragOverlay = "dragOverlay"

    // MARK: - Context Menu Actions (UI-testing accessible)
    static let openSettingsContextButton = "openSettingsContextButton"
    static let uiTestAppRootRefreshStatus = "uiTestAppRootRefreshStatus"
}
