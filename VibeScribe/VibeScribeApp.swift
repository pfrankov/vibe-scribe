//
//  VibeScribeApp.swift
//  VibeScribe
//
//  Created by Pavel Frankov on 13.04.2025.
//

import SwiftUI
import SwiftData
import AppKit
import AVFoundation

private enum UITestDefaultsKey {
    static let launchPermissionStatus = "ui.test.launch.permission.status"
}

enum UITestEnvironmentKey {
    static let dataScenario = "VIBESCRIBE_UI_DATA_SCENARIO"
    static let playbackProgress = "VIBESCRIBE_UI_PLAYBACK_PROGRESS"
    static let openMainWindow = "VIBESCRIBE_UI_OPEN_MAIN_WINDOW"
}

enum UITestDataScenario: String {
    case standard
    case executiveDemoScreenshot = "executive_demo_screenshot"
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarItem: NSStatusItem?
    var mainWindow: NSWindow?

    private var isUITestingProcess: Bool {
        let env = ProcessInfo.processInfo.environment
        return ProcessInfo.processInfo.arguments.contains("--uitesting")
            || env["VIBESCRIBE_UI_TESTING"] == "1"
            || env["VIBESCRIBE_UI_USE_MOCK_PIPELINE"] == "1"
            || env["XCTestConfigurationFilePath"] != nil
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBarItem()
        updateLaunchPermissionProbe(status: "microphone_only")
        scheduleUITestMainWindowOpenIfNeeded()

        // Skip permission requests during UI testing to avoid system dialogs
        guard !isUITestingProcess else { return }

        requestPermissions { granted in
            if granted {
                Logger.info("Launch-time microphone permission granted", category: .general)
            } else {
                Logger.warning("Launch-time microphone permission was denied", category: .general)
                DispatchQueue.main.async {
                    self.showPermissionAlert()
                }
            }
        }
    }
    
    private func setupStatusBarItem() {
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        guard let button = statusBarItem?.button else { return }
        
        button.image = NSImage(named: "MenuBarIcon")
        button.action = #selector(statusBarButtonClicked)
        button.target = self
        
        let menu = NSMenu()
        
        // Open main window
        menu.addItem(NSMenuItem(
            title: AppLanguage.localized("open"),
            action: #selector(openMainWindow),
            keyEquivalent: "o"
        ))
        
        // Start recording
        menu.addItem(NSMenuItem(
            title: AppLanguage.localized("start.recording"),
            action: #selector(startRecording),
            keyEquivalent: "r"
        ))
        
        menu.addItem(NSMenuItem.separator())
        
        // Settings
        menu.addItem(NSMenuItem(
            title: AppLanguage.localized("settings"),
            action: #selector(openSettings),
            keyEquivalent: ","
        ))
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit application
        menu.addItem(NSMenuItem(
            title: AppLanguage.localized("quit"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        
        statusBarItem?.menu = menu
    }
    
    @objc func statusBarButtonClicked() {
        if let window = mainWindow {
            if window.isVisible {
                window.orderOut(nil)
            } else {
                window.makeKeyAndOrderFront(nil)
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
        } else {
            openMainWindow()
        }
    }
    
    @objc func openMainWindow() {
        if let window = mainWindow {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        } else if let window = NSApplication.shared.windows.first {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            mainWindow = window
        }
    }
    
    @objc func startRecording() {
        openMainWindow()
        // Notify the UI to start recording
        NotificationCenter.default.post(name: NSNotification.Name("StartRecording"), object: nil)
    }
    
    @objc func openSettings() {
        if let window = mainWindow ?? NSApplication.shared.windows.first {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NotificationCenter.default.post(name: NSNotification.Name("ShowSettings"), object: nil)
            }
        }
    }
    
    private func requestPermissions(completion: @escaping (Bool) -> Void) {
        updateLaunchPermissionProbe(status: "microphone_only")
        guard !isUITestingProcess else {
            completion(true)
            return
        }

        // Request Microphone access
        AVCaptureDevice.requestAccess(for: .audio) { micGranted in
            completion(micGranted)
        }
    }

    private func updateLaunchPermissionProbe(status: String) {
        guard isUITestingProcess else { return }
        UserDefaults.standard.set(status, forKey: UITestDefaultsKey.launchPermissionStatus)
    }

    private func scheduleUITestMainWindowOpenIfNeeded(retryCount: Int = 0) {
        guard isUITestingProcess else { return }
        guard ProcessInfo.processInfo.environment[UITestEnvironmentKey.openMainWindow] == "1" else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if let window = self.preferredUITestWindow() {
                self.mainWindow = window
                window.makeKeyAndOrderFront(nil)
                NSApplication.shared.activate(ignoringOtherApps: true)
                return
            }

            if retryCount >= 12 {
                self.createUITestFallbackMainWindow()
                return
            }
            self.scheduleUITestMainWindowOpenIfNeeded(retryCount: retryCount + 1)
        }
    }

    private func preferredUITestWindow() -> NSWindow? {
        if let mainWindow, mainWindow.contentViewController != nil {
            return mainWindow
        }

        if let visibleWindow = NSApplication.shared.windows.first(where: { window in
            window.contentViewController != nil && !window.isMiniaturized && window.isVisible
        }) {
            return visibleWindow
        }

        if let existingWindow = NSApplication.shared.windows.first(where: { window in
            window.contentViewController != nil && !window.isMiniaturized
        }) {
            return existingWindow
        }

        return nil
    }

    private func createUITestFallbackMainWindow() {
        guard preferredUITestWindow() == nil else { return }

        let rootView = ContentView()
            .modelContainer(VibeScribeApp.fallbackUITestingContainer)
            .environment(\.locale, VibeScribeApp.fallbackUITestingLocale)

        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 160, y: 120, width: 1500, height: 980),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        mainWindow = window
    }
    
    private func showPermissionAlert() {
        guard !isUITestingProcess else { return }
        let alert = NSAlert()
        alert.messageText = AppLanguage.localized("microphone.permission.required")
        alert.informativeText = AppLanguage.localized("vibescribe.needs.microphone.access.to.record.audio.please.grant.permission.in.system.preferences.security.privacy.microphone")
        alert.alertStyle = .warning
        alert.addButton(withTitle: AppLanguage.localized("open.system.preferences"))
        alert.addButton(withTitle: AppLanguage.localized("cancel"))
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // Open System Preferences
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

@main
struct VibeScribeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("ui.language.code") private var appLanguageCode: String = ""
    @AppStorage(UITestDefaultsKey.launchPermissionStatus) private var uiTestLaunchPermissionStatus = "idle"
    @State private var uiTestAppRootRefreshGeneration = 0
    @State private var uiTestAppRootRefreshStatus = "idle"
    @State private var didScheduleUITestAppRootRefresh = false

    private static let hasXCTestConfiguration = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    private static let uiTestingEnvEnabled = ProcessInfo.processInfo.environment["VIBESCRIBE_UI_TESTING"] == "1"
    private static let emptyStateEnvEnabled = ProcessInfo.processInfo.environment["VIBESCRIBE_UI_EMPTY_STATE"] == "1"
    private static let forceAppBodyRefreshEnvEnabled = ProcessInfo.processInfo.environment["VIBESCRIBE_UI_FORCE_APP_BODY_REFRESH"] == "1"
    private static let launchPermissionProbeEnvEnabled = ProcessInfo.processInfo.environment["VIBESCRIBE_UI_EXPOSE_LAUNCH_PERMISSION_PROBE"] == "1"
    private static let uiTestDataScenario = UITestDataScenario(
        rawValue: ProcessInfo.processInfo.environment[UITestEnvironmentKey.dataScenario] ?? ""
    ) ?? .standard

    static let isUITesting =
        ProcessInfo.processInfo.arguments.contains("--uitesting")
        || uiTestingEnvEnabled
        || hasXCTestConfiguration
    static let isEmptyState =
        ProcessInfo.processInfo.arguments.contains("--empty-state")
        || emptyStateEnvEnabled

    private static let sharedModelContainer: ModelContainer = {
        do {
            return try ModelContainer(
                for: Record.self,
                Tag.self,
                AppSettings.self,
                RecordSpeakerSegment.self,
                SpeakerProfile.self
            )
        } catch {
            fatalError("Failed to create shared model container: \(error)")
        }
    }()

    private var appLocale: Locale {
        AppLanguage.applyPreferredLanguagesIfNeeded(code: appLanguageCode)
        return AppLanguage.locale(for: appLanguageCode)
    }

    private var activeModelContainer: ModelContainer {
        Self.isUITesting ? Self.uiTestingContainer : Self.sharedModelContainer
    }

    static var fallbackUITestingContainer: ModelContainer {
        uiTestingContainer
    }

    static var fallbackUITestingLocale: Locale {
        AppLanguage.locale(for: AppLanguage.storedCode)
    }

    init() {
        // Keep UI-test startup deterministic even if a previous manual/dev session toggled
        // the debug empty-state switch persisted in UserDefaults.
        if Self.isUITesting {
            UserDefaults.standard.set(false, forKey: "debug.simulateEmptyRecordings")
            UserDefaults.standard.set("idle", forKey: UITestDefaultsKey.launchPermissionStatus)
        }
    }

    private static let uiTestingContainer: ModelContainer = {
        do {
            let schema = Schema([Record.self, Tag.self, AppSettings.self, RecordSpeakerSegment.self, SpeakerProfile.self])
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            let container = try ModelContainer(for: schema, configurations: [config])

            if !isEmptyState {
                seedTestData(in: container.mainContext, scenario: uiTestDataScenario)
            }
            return container
        } catch {
            fatalError("Failed to create UI testing container: \(error)")
        }
    }()

    @MainActor
    private static func seedTestData(in context: ModelContext, scenario: UITestDataScenario) {
        switch scenario {
        case .standard:
            seedStandardTestData(in: context)
        case .executiveDemoScreenshot:
            seedExecutiveDemoScreenshotData(in: context)
        }
    }

    @MainActor
    private static func seedStandardTestData(in context: ModelContext) {
        let settings = AppSettings()
        context.insert(settings)

        let tag1 = Tag(name: "meeting")
        let tag2 = Tag(name: "important")
        let tag3 = Tag(name: "personal")
        context.insert(tag1)
        context.insert(tag2)
        context.insert(tag3)

        let record1 = Record(
            name: "Team Standup March 15",
            fileURL: nil,
            duration: 1845
        )
        record1.transcriptionText = "This is a sample transcription of the team standup meeting. We discussed the progress on the new feature and identified some blockers."
        record1.summaryText = "## Team Standup Summary\n\n- Feature development on track\n- Two blockers identified\n- Next review scheduled for Friday"
        record1.tags = [tag1, tag2]
        context.insert(record1)

        let record2 = Record(
            name: "Client Call",
            fileURL: nil,
            duration: 3600
        )
        record2.transcriptionText = "Discussion with client about project requirements and timeline adjustments."
        record2.tags = [tag1]
        context.insert(record2)

        let record3 = Record(
            name: "Voice Note",
            fileURL: nil,
            duration: 120
        )
        record3.tags = [tag3]
        context.insert(record3)

        try? context.save()
    }

    @MainActor
    private static func seedExecutiveDemoScreenshotData(in context: ModelContext) {
        let settings = AppSettings()
        settings.openAIBaseURL = "http://localhost:11434/v1/"
        settings.openAIModel = "gpt-oss-20b"
        settings.whisperProvider = .defaultProvider
        settings.enableSpeakerDiarization = true
        context.insert(settings)

        let sprintReview = Tag(name: "SprintReview")
        let releaseReadiness = Tag(name: "ReleaseReadiness")
        let incidentReview = Tag(name: "IncidentReview")
        let oneOnOne = Tag(name: "OneOnOne")
        let hiring = Tag(name: "Hiring")
        let planning = Tag(name: "Planning")
        for tag in [sprintReview, releaseReadiness, incidentReview, oneOnOne, hiring, planning] {
            context.insert(tag)
        }

        let demoAudioURL = try? uiTestDemoAudioURL(
            named: "team-lead-demo-summary-v4.wav",
            duration: 12 * 60,
            toneSeed: 13
        )

        let teamLead = SpeakerProfile(
            speakerId: "speaker_team_lead",
            displayName: "Nina Torres",
            colorHue: 0.09,
            embedding: [],
            totalDuration: 260
        )
        let seniorBackendEngineer = SpeakerProfile(
            speakerId: "speaker_senior_backend_engineer",
            displayName: "Alex Chen",
            colorHue: 0.60,
            embedding: [],
            totalDuration: 460
        )
        context.insert(teamLead)
        context.insert(seniorBackendEngineer)

        let executiveRecord = Record(
            name: "Sprint Risk Review - Payments Rollout",
            fileURL: demoAudioURL,
            date: uiTestDate(year: 2026, month: 3, day: 28, hour: 8, minute: 45),
            duration: 12 * 60,
            hasTranscription: true,
            transcriptionText: """
We reviewed whether the payments rollout can stay in this sprint, which alerts still wake Alex up for no reason, and how to keep the staff backend hiring loop moving without stealing interview time from the release week. Nina agreed to freeze non-critical merges late Wednesday, run one rollback rehearsal before code freeze, move the batch export cleanup out of sprint, and keep Daniel Park's final panel on next week's calendar.
""",
            summaryText: """
- **Status:** Payments rollout stays on track for Thursday, but retry queue saturation is still the only high-risk blocker.
- **Decision:** Freeze non-critical merges after Wednesday 18:00 and move batch export cleanup to next sprint.
- **Owners:** Nina Torres runs the rollback rehearsal today; Alex Chen fixes the flaky refund test; Priya Nair trims alert noise before tomorrow's handoff.
- **People:** Keep the staff backend opening active and book Daniel Park's final panel for next week.
- **Watch-outs:** One infra approval is still pending; if it slips, the fallback is a two-day release delay.
- **Why this recording matters:** Decisions, owners, and risks are already captured, so the lead can leave the meeting and execute instead of rewriting notes.
""",
            includesSystemAudio: true,
            tags: [sprintReview, releaseReadiness]
        )
        context.insert(executiveRecord)

        let executiveSegments = [
            RecordSpeakerSegment(startTime: 0, endTime: 104, qualityScore: 0.95, record: executiveRecord, speaker: teamLead),
            RecordSpeakerSegment(startTime: 104, endTime: 252, qualityScore: 0.94, record: executiveRecord, speaker: seniorBackendEngineer),
            RecordSpeakerSegment(startTime: 252, endTime: 418, qualityScore: 0.96, record: executiveRecord, speaker: teamLead),
            RecordSpeakerSegment(startTime: 418, endTime: 720, qualityScore: 0.93, record: executiveRecord, speaker: seniorBackendEngineer),
        ]
        executiveRecord.speakerSegments = executiveSegments
        executiveRecord.lastDiarizationAt = uiTestDate(year: 2026, month: 3, day: 28, hour: 8, minute: 57)
        teamLead.segments = executiveSegments.filter { $0.speaker?.id == teamLead.id }
        seniorBackendEngineer.segments = executiveSegments.filter { $0.speaker?.id == seniorBackendEngineer.id }
        executiveSegments.forEach(context.insert)

        let boardRecord = Record(
            name: "Incident Review - Checkout Retry Storm",
            fileURL: nil,
            date: uiTestDate(year: 2026, month: 3, day: 27, hour: 16, minute: 30),
            duration: 31 * 60,
            hasTranscription: true,
            transcriptionText: "Reviewed root cause, noisy retry behavior, and the two mitigations needed before the next on-call shift.",
            includesSystemAudio: true,
            tags: [incidentReview]
        )
        context.insert(boardRecord)

        let oneOnOneRecord = Record(
            name: "1:1 with Alex Chen",
            fileURL: nil,
            date: uiTestDate(year: 2026, month: 3, day: 26, hour: 14, minute: 15),
            duration: 29 * 60,
            hasTranscription: true,
            transcriptionText: "Discussed promotion goals, ownership scope after the payments rollout, and where mentoring time is getting squeezed by incident noise.",
            summaryText: """
- **Career:** Candidate is ready for broader service ownership after the rollout.
- **Support needed:** Protect one uninterrupted focus block per week and pair on stakeholder updates.
- **Follow-up:** Draft a growth plan before the next monthly 1:1.
""",
            tags: [oneOnOne]
        )
        context.insert(oneOnOneRecord)

        let vendorRecord = Record(
            name: "Hiring Debrief - Daniel Park",
            fileURL: nil,
            date: uiTestDate(year: 2026, month: 3, day: 25, hour: 12, minute: 0),
            duration: 37 * 60,
            tags: [hiring]
        )
        context.insert(vendorRecord)

        let talentRecord = Record(
            name: "Planning Sync - Q2 Platform Goals",
            fileURL: nil,
            date: uiTestDate(year: 2026, month: 3, day: 24, hour: 10, minute: 30),
            duration: 24 * 60,
            hasTranscription: true,
            transcriptionText: "Reviewed reliability goals, cross-team dependencies, and what the platform team can realistically ship without burning on-call capacity.",
            summaryText: """
- **Focus:** Reliability, alert reduction, and one self-serve developer workflow.
- **Constraint:** Keep roadmap scope realistic while the team is still absorbing on-call load.
- **Next step:** Reconfirm cross-team dependencies before sprint planning.
""",
            tags: [planning]
        )
        context.insert(talentRecord)

        try? context.save()
    }

    private static func uiTestDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return components.date ?? Date(timeIntervalSince1970: 0)
    }

    private static func uiTestDemoAudioURL(named fileName: String, duration: TimeInterval, toneSeed: Int) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VibeScribeUITestAudio", isDirectory: true)

        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let url = directory.appendingPathComponent(fileName)
        if !FileManager.default.fileExists(atPath: url.path) {
            try writeUITestWaveformFixture(to: url, duration: duration, toneSeed: toneSeed)
        }
        return url
    }

    private static func writeUITestWaveformFixture(to url: URL, duration: TimeInterval, toneSeed: Int) throws {
        let sampleRate: UInt32 = 8_000
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let bytesPerSample = Int(channels * (bitsPerSample / 8))
        let sampleCount = Int(duration * Double(sampleRate))
        let dataSize = sampleCount * bytesPerSample
        let byteRate = sampleRate * UInt32(bytesPerSample)
        let blockAlign = channels * (bitsPerSample / 8)
        let riffChunkSize = UInt32(36 + dataSize)

        var data = Data()
        data.append(contentsOf: Array("RIFF".utf8))
        appendLittleEndian(riffChunkSize, to: &data)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        appendLittleEndian(UInt32(16), to: &data)
        appendLittleEndian(UInt16(1), to: &data)
        appendLittleEndian(channels, to: &data)
        appendLittleEndian(sampleRate, to: &data)
        appendLittleEndian(byteRate, to: &data)
        appendLittleEndian(blockAlign, to: &data)
        appendLittleEndian(bitsPerSample, to: &data)
        data.append(contentsOf: Array("data".utf8))
        appendLittleEndian(UInt32(dataSize), to: &data)

        let framesPerSecond = 100
        let samplesPerFrame = max(1, Int(sampleRate) / framesPerSecond)
        let totalFrames = Int(ceil(Double(sampleCount) / Double(samplesPerFrame)))
        let speakerRegions: [(startFrame: Int, endFrame: Int, style: SpeechStyle)] = [
            (0, 104 * framesPerSecond, SpeechStyle(phraseRange: 0.9...2.2, pauseRange: 0.16...0.55, energyRange: 0.42...0.76, baseFrequency: 148, noiseMix: 0.14)),
            (104 * framesPerSecond, 252 * framesPerSecond, SpeechStyle(phraseRange: 1.4...3.3, pauseRange: 0.08...0.28, energyRange: 0.50...0.92, baseFrequency: 112, noiseMix: 0.10)),
            (252 * framesPerSecond, 418 * framesPerSecond, SpeechStyle(phraseRange: 0.8...1.8, pauseRange: 0.14...0.44, energyRange: 0.40...0.72, baseFrequency: 152, noiseMix: 0.15)),
            (418 * framesPerSecond, totalFrames, SpeechStyle(phraseRange: 1.2...3.8, pauseRange: 0.10...0.34, energyRange: 0.48...0.88, baseFrequency: 118, noiseMix: 0.11)),
        ]

        var frameEnvelopes = Array(repeating: 0.0, count: totalFrames)
        var frameCursor = 0
        var frameRNG = LCG(seed: UInt64(bitPattern: Int64(max(toneSeed, 1))))

        while frameCursor < totalFrames {
            let style = speechStyle(atFrame: frameCursor, regions: speakerRegions)
            let phraseFrames = Int(style.random(in: style.phraseRange, using: &frameRNG) * Double(framesPerSecond))
            let pauseFrames = Int(style.random(in: style.pauseRange, using: &frameRNG) * Double(framesPerSecond))
            let phraseEnergy = style.random(in: style.energyRange, using: &frameRNG)
            var phraseCursor = 0

            while phraseCursor < phraseFrames, frameCursor + phraseCursor < totalFrames {
                let wordFrames = max(4, Int((0.07 + frameRNG.nextUnit() * 0.24) * Double(framesPerSecond)))
                let gapFrames = Int((0.02 + frameRNG.nextUnit() * 0.09) * Double(framesPerSecond))
                let syllableCount = 1 + Int(frameRNG.nextUnit() * 3.0)
                var localCursor = 0

                for syllableIndex in 0..<syllableCount where localCursor < wordFrames {
                    let remainingFrames = max(2, wordFrames - localCursor)
                    let targetFrames = max(2, remainingFrames / max(syllableCount - syllableIndex, 1))
                    let syllableFrames = min(
                        remainingFrames,
                        max(2, targetFrames + Int((frameRNG.nextUnit() - 0.5) * 6.0))
                    )
                    let syllableEnergy = phraseEnergy * (0.72 + frameRNG.nextUnit() * 0.38)

                    for localIndex in 0..<syllableFrames {
                        let globalFrame = frameCursor + phraseCursor + localCursor + localIndex
                        guard globalFrame < totalFrames else { break }

                        let progress = Double(localIndex) / Double(max(syllableFrames - 1, 1))
                        let contour = pow(sin(progress * .pi), 0.85)
                        let flutter = 0.88 + 0.16 * sin((Double(syllableIndex) * 0.9) + Double(localIndex) * 0.43)
                        let microAccent = 0.92 + 0.20 * frameRNG.nextUnit()
                        frameEnvelopes[globalFrame] = max(
                            frameEnvelopes[globalFrame],
                            min(1.0, syllableEnergy * contour * flutter * microAccent)
                        )
                    }

                    localCursor += syllableFrames
                    localCursor += Int(frameRNG.nextUnit() * 3.0)
                }

                phraseCursor += wordFrames + gapFrames
            }

            frameCursor += phraseFrames + pauseFrames
        }

        var sampleRNG = LCG(seed: UInt64(bitPattern: Int64(max(toneSeed * 97, 1))))
        var noiseState = 0.0
        var breathState = 0.0

        for sampleIndex in 0..<sampleCount {
            let time = Double(sampleIndex) / Double(sampleRate)
            let frameIndex = min(totalFrames - 1, sampleIndex / samplesPerFrame)
            let envelope = frameEnvelopes[frameIndex]
            let style = speechStyle(atFrame: frameIndex, regions: speakerRegions)
            let pitchDrift = 1.0
                + 0.018 * sin(2 * .pi * 0.37 * time)
                + 0.011 * sin(2 * .pi * 1.21 * time + 0.7)
            let carrier = sin(2 * .pi * style.baseFrequency * pitchDrift * time)
            let harmonic = 0.46 * sin(2 * .pi * style.baseFrequency * 1.93 * time + 0.4)
            let upperFormant = 0.22 * sin(2 * .pi * style.baseFrequency * 3.2 * time + 1.1)

            let whiteNoise = sampleRNG.nextSignedUnit()
            noiseState = (noiseState * 0.88) + (whiteNoise * 0.12)
            breathState = (breathState * 0.94) + (sampleRNG.nextSignedUnit() * 0.06)
            let shimmer = 0.90 + 0.14 * sin(2 * .pi * (6.0 + sampleRNG.nextUnit() * 2.5) * time)

            let speechBody = (carrier + harmonic + upperFormant) * shimmer
            let waveform = max(
                -1.0,
                min(1.0, envelope * (0.66 * speechBody + style.noiseMix * noiseState + 0.07 * breathState))
            )
            let sample = Int16((waveform * 30_000).rounded())
            appendLittleEndian(sample, to: &data)
        }

        try data.write(to: url, options: .atomic)
    }

    private struct SpeechStyle {
        let phraseRange: ClosedRange<Double>
        let pauseRange: ClosedRange<Double>
        let energyRange: ClosedRange<Double>
        let baseFrequency: Double
        let noiseMix: Double

        func random(in range: ClosedRange<Double>, using rng: inout LCG) -> Double {
            range.lowerBound + (range.upperBound - range.lowerBound) * rng.nextUnit()
        }
    }

    private struct LCG {
        private var state: UInt64

        init(seed: UInt64) {
            self.state = seed == 0 ? 0xfeedface : seed
        }

        mutating func nextUnit() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double((state >> 11) & 0x1F_FFFF) / Double(0x1F_FFFF)
        }

        mutating func nextSignedUnit() -> Double {
            (nextUnit() * 2.0) - 1.0
        }
    }

    private static func speechStyle(atFrame frameIndex: Int, regions: [(startFrame: Int, endFrame: Int, style: SpeechStyle)]) -> SpeechStyle {
        if let region = regions.first(where: { frameIndex >= $0.startFrame && frameIndex < $0.endFrame }) {
            return region.style
        }
        return regions.last?.style ?? SpeechStyle(
            phraseRange: 1.0...2.0,
            pauseRange: 0.2...0.4,
            energyRange: 0.5...0.8,
            baseFrequency: 128,
            noiseMix: 0.12
        )
    }

    private static func appendLittleEndian<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { bytes in
            data.append(bytes.bindMemory(to: UInt8.self))
        }
    }

    private var shouldExposeUITestRootRefreshProbe: Bool {
        Self.isUITesting && Self.forceAppBodyRefreshEnvEnabled
    }

    private var shouldExposeUITestLaunchPermissionProbe: Bool {
        Self.isUITesting && Self.launchPermissionProbeEnvEnabled
    }

    @ViewBuilder
    private var uiTestLaunchPermissionProbe: some View {
        if shouldExposeUITestLaunchPermissionProbe {
            Text(uiTestLaunchPermissionStatus)
                .font(.caption2)
                .foregroundStyle(.clear)
                .frame(width: 1, height: 1)
                .clipped()
                .allowsHitTesting(false)
                .accessibilityIdentifier(AccessibilityID.uiTestLaunchPermissionStatus)
        }
    }

    @ViewBuilder
    private var uiTestRootRefreshProbe: some View {
        if shouldExposeUITestRootRefreshProbe {
            Text(uiTestAppRootRefreshStatus)
                .font(.caption2)
                .foregroundStyle(.clear)
                .frame(width: 1, height: 1)
                .clipped()
                .allowsHitTesting(false)
                .accessibilityIdentifier(AccessibilityID.uiTestAppRootRefreshStatus)
        }
    }

    private func scheduleUITestAppRootRefreshIfNeeded() {
        guard shouldExposeUITestRootRefreshProbe, !didScheduleUITestAppRootRefresh else { return }

        didScheduleUITestAppRootRefresh = true
        uiTestAppRootRefreshStatus = "pending"

        // Force a deterministic App.body recomputation after the initial detail selection path runs.
        DispatchQueue.main.async {
            uiTestAppRootRefreshGeneration += 1
            uiTestAppRootRefreshStatus = "completed"
        }
    }

    var body: some Scene {
        let _ = uiTestAppRootRefreshGeneration

        WindowGroup {
            ContentView()
                .background {
                    ZStack {
                        uiTestLaunchPermissionProbe
                        uiTestRootRefreshProbe
                    }
                }
                .onAppear {
                    scheduleUITestAppRootRefreshIfNeeded()
                }
                .modelContainer(activeModelContainer)
                .environment(\.locale, appLocale)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .newItem) { }

            CommandGroup(after: .appInfo) {
                Button(AppLanguage.localized("settings.ellipsis")) {
                    appDelegate.openSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
