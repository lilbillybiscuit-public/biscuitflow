import AppKit
import Combine
import Foundation

/// Orchestrates a dictation: hotkey → record → transcribe → clean up → paste.
@MainActor
final class DictationController: ObservableObject {
    enum Phase: Equatable {
        case idle
        case recording(handsFree: Bool)
        case transcribing
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var modelState: Transcriber.State = .notLoaded
    /// Recent input levels (0…1), newest last, for the waveform.
    @Published private(set) var levels: [Float] = Array(repeating: 0, count: 24)
    /// Transient message shown above the dictation pill (errors, hints).
    @Published private(set) var toast: String?
    @Published private(set) var lastResult: HistoryItem?

    let settings: AppSettings
    let store: Store
    let permissions: Permissions

    private let hotkeys = HotkeyMonitor()
    private let recorder = AudioRecorder()
    private let sounds = SoundPlayer()
    private lazy var transcriber = Transcriber { [weak self] state in
        Task { @MainActor in self?.modelState = state }
    }

    /// When the current recording began (drives the pill's elapsed-time counter).
    @Published private(set) var recordingStartedAt = Date()
    private var recordingContext: TextInserter.FocusContext?
    private var maxDurationTimer: Timer?
    private var toastTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    /// Hands-free recordings stop automatically after this long.
    private let maxRecordingSeconds: TimeInterval = 6 * 60

    init(settings: AppSettings, store: Store, permissions: Permissions) {
        self.settings = settings
        self.store = store
        self.permissions = permissions

        recorder.onLevel = { [weak self] level in self?.push(level: level) }

        hotkeys.isRecording = { [weak self] in
            if case .recording = self?.phase { return true }
            return false
        }
        hotkeys.isHandsFreeActive = { [weak self] in self?.phase == .recording(handsFree: true) }
        hotkeys.onEvent = { [weak self] event in self?.handle(event) }

        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.applySettings() }
            .store(in: &cancellables)
    }

    // MARK: - Lifecycle

    func start() {
        applySettings()
        startHotkeysIfPossible()
        loadModel()
    }

    func startHotkeysIfPossible() {
        permissions.refresh()
        guard permissions.accessibility, !hotkeys.isRunning else { return }
        hotkeys.start()
    }

    func loadModel() {
        Task { await transcriber.load() }
    }

    private func applySettings() {
        // AppStorage publishes before the new value lands; read on the next tick.
        DispatchQueue.main.async { [self] in
            hotkeys.hotkey = settings.hotkey
            hotkeys.doubleTapEnabled = settings.handsFreeDoubleTap
        }
    }

    // MARK: - Hotkey events

    private func handle(_ event: HotkeyMonitor.Event) {
        switch event {
        case .pressBegan:
            beginRecording(handsFree: false)
        case .lockHandsFree:
            guard case .recording = phase else { return }
            phase = .recording(handsFree: true)
            if settings.playSounds { sounds.play(.lock) }
        case .pressEnded, .toggleStop:
            finishRecording()
        case .cancel:
            cancelRecording(showToast: false)
        case .tapTooShort:
            cancelRecording(showToast: false, playSound: false)
            showToast(settings.handsFreeDoubleTap
                      ? "Hold \(settings.hotkey.displayName) to talk · double-tap for hands-free"
                      : "Hold \(settings.hotkey.displayName) to talk")
        }
    }

    /// Toggle for the menu-bar item and pill clicks: start hands-free, or stop.
    func toggleHandsFree() {
        if case .recording = phase {
            finishRecording()
        } else {
            beginRecording(handsFree: true)
        }
    }

    /// Pauses the global hotkey while the Settings recorder captures a new shortcut.
    func setHotkeySuspended(_ suspended: Bool) { hotkeys.isSuspended = suspended }

    func cancelFromUI() { cancelRecording(showToast: false) }

    /// Re-pastes the most recent transcript (menu item).
    func pasteLast() {
        guard let text = store.history.first?.text else { return }
        TextInserter.insert(text, restoreClipboard: settings.restoreClipboard)
    }

    // MARK: - Recording

    private func beginRecording(handsFree: Bool) {
        guard case .idle = phase else {
            if phase == .transcribing { showToast("Still transcribing…") }
            return
        }
        permissions.refresh()
        guard permissions.microphone == .authorized || AudioRecorder.testAudioPath != nil else {
            showToast("Microphone access needed")
            permissions.requestMicrophone()
            return
        }
        if case .failed(let message) = modelState {
            showToast("Model failed to load: \(message)")
            return
        }

        do {
            try recorder.start(deviceUID: settings.microphoneUID)
        } catch {
            showToast(error.localizedDescription)
            return
        }
        recordingStartedAt = Date()
        recordingContext = nil
        levels = Array(repeating: 0, count: levels.count)
        phase = .recording(handsFree: handsFree)
        toast = nil
        if settings.playSounds { sounds.play(handsFree ? .lock : .start) }
        if settings.muteAudioWhileDictating {
            // Let our start cue finish before muting the output.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                if case .recording = self?.phase { SystemAudio.muteOutput() }
            }
        }

        maxDurationTimer?.invalidate()
        maxDurationTimer = Timer.scheduledTimer(withTimeInterval: maxRecordingSeconds, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.finishRecording() }
        }
    }

    private func cancelRecording(showToast: Bool, playSound: Bool = true) {
        guard case .recording = phase else { return }
        maxDurationTimer?.invalidate()
        recorder.stop()
        SystemAudio.restoreOutput()
        phase = .idle
        if playSound, settings.playSounds { sounds.play(.cancel) }
        if showToast { self.showToast("Cancelled") }
    }

    private func finishRecording() {
        guard case .recording = phase else { return }
        maxDurationTimer?.invalidate()
        let samples = recorder.stop()
        SystemAudio.restoreOutput()
        if settings.playSounds { sounds.play(.stop) }

        let seconds = Double(samples.count) / AudioRecorder.targetSampleRate
        guard seconds >= 0.3, Self.containsSpeech(samples) else {
            phase = .idle
            showToast("Didn't catch that")
            return
        }

        phase = .transcribing
        // Read the caret context now, while the target app is still focused.
        let focus = TextInserter.focusContext()
        let language = settings.language == "auto" ? nil : settings.language
        let context = store.biasingContext

        Task {
            do {
                if !(await transcriber.isReady) {
                    showToast("Loading speech model…")
                    while !(await transcriber.isReady) {
                        if case .failed = modelState { throw NSError(domain: "BiscuitFlow", code: 2, userInfo: [NSLocalizedDescriptionKey: "Speech model unavailable"]) }
                        try await Task.sleep(for: .milliseconds(200))
                    }
                }
                let result = try await transcriber.transcribe(samples, language: language, context: context)
                deliver(result, focus: focus)
            } catch {
                showToast(error.localizedDescription)
            }
            if phase == .transcribing { phase = .idle }
        }
    }

    private func deliver(_ result: Transcriber.Result, focus: TextInserter.FocusContext) {
        let processor = TextProcessor(
            removeFillers: settings.removeFillerWords,
            smartSpacing: settings.smartSpacing,
            replacements: store.dictionary,
            snippets: store.snippets)
        let text = processor.process(result.text, context: focus)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showToast("Didn't catch that")
            return
        }

        if permissions.accessibility {
            TextInserter.insert(text, restoreClipboard: settings.restoreClipboard)
        } else {
            TextInserter.copyToClipboard(text)
            showToast("Copied — grant Accessibility to paste automatically")
        }

        let item = HistoryItem(
            date: Date(), text: text.trimmingCharacters(in: .whitespaces), rawText: result.text,
            appName: focus.appName, bundleID: focus.bundleID,
            audioSeconds: result.audioSeconds, inferenceSeconds: result.inferenceSeconds)
        store.add(item)
        lastResult = item
        NSLog("[BiscuitFlow] %.1fs audio → %.2fs inference: %@", result.audioSeconds, result.inferenceSeconds, text)
    }

    /// Rejects near-silent clips so the model doesn't hallucinate on room noise.
    nonisolated static func containsSpeech(_ samples: [Float]) -> Bool {
        let window = 1600 // 100 ms
        var loudWindows = 0
        var i = 0
        while i + window <= samples.count {
            var sum: Float = 0
            for j in i..<(i + window) { sum += samples[j] * samples[j] }
            if sqrtf(sum / Float(window)) > 0.008 { loudWindows += 1 }
            if loudWindows >= 2 { return true }
            i += window
        }
        return false
    }

    // MARK: - UI helpers

    private func push(level: Float) {
        guard case .recording = phase else { return }
        levels.removeFirst()
        levels.append(level)
    }

    func showToast(_ message: String) {
        toast = message
        toastTimer?.invalidate()
        toastTimer = Timer.scheduledTimer(withTimeInterval: 2.6, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.toast = nil }
        }
    }
}
