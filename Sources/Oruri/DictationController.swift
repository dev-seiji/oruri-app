import AVFoundation
import AppKit

/// Orquestra o ditado: gravar → transcrever → pipeline de texto → limpeza por IA → entregar → histórico.
/// Também processa a fila de arquivos arrastados (um por vez).
@MainActor
final class DictationController {
    private let state: AppState
    private let recorder = AudioRecorder()
    private let hotkeys = HotkeyMonitor()
    /// Players pausados no início da gravação (só os que estavam tocando).
    private var pausedPlayers: [String] = []
    private var warnedChromeBlocked = false
    private var fileQueue: [URL] = []
    private var processingFiles = false
    /// Pede a permissão de Acessibilidade ao sistema no máximo uma vez por sessão.
    private var askedForAccessibility = false

    /// Acima disso a gravação é considerada "longa" (vai só para a área de transferência).
    private static let longRecordingSeconds: TimeInterval = 5 * 60
    /// Gravações mais curtas que isso são descartadas como toque acidental.
    private static let minimumSeconds: TimeInterval = 0.4

    init(state: AppState) {
        self.state = state
        recorder.onLevel = { [weak state] level in
            DispatchQueue.main.async { state?.audioLevel = level }
        }
        hotkeys.onStart = { [weak self] in self?.start() }
        hotkeys.onStop = { [weak self] in self?.stop() }
        hotkeys.onCancel = { [weak self] in self?.cancel() }
        hotkeys.isRecording = { [weak state] in state?.isRecording ?? false }
        applySettings()
        hotkeys.start()
        Store.purgeOrphanAudio(keeping: state.recordings)
        applyRetention()
    }

    /// Chamado quando as configurações mudam.
    func applySettings() {
        let s = state.settings
        hotkeys.triggers = s.triggers
        hotkeys.holdToRecord = s.holdToRecord
        hotkeys.handsFree = s.handsFree
    }

    func restartHotkeys() { hotkeys.start() }

    // MARK: Gravação

    func toggle() {
        switch state.phase {
        case .idle: start()
        case .recording: stop()
        case .transcribing: break
        }
    }

    func start() {
        guard state.phase == .idle else { return }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async { if granted { self.start() } }
            }
            return
        default:
            state.showToast(T("Microphone access is off. Allow it in System Settings › Privacy & Security."))
            return
        }

        let s = state.settings
        let deviceUID = s.microphone == "System Default" ? nil : s.microphone
        do {
            try recorder.start(deviceUID: deviceUID)
        } catch {
            state.showToast(error.localizedDescription)
            return
        }
        if s.playSound { SystemIntegration.playStartSound() }
        // Ícone do app em que o texto vai entrar, mostrado na bolha.
        state.dictationAppIcon = NSWorkspace.shared.frontmostApplication?.icon
        state.phase = .recording
        // A pausa da música roda em segundo plano; se a gravação já acabou quando ela termina, retoma na hora.
        if s.pauseMedia {
            SystemIntegration.pausePlayingMedia { [weak self] players, chromeBlocked in
                guard let self else { return }
                if self.state.phase == .recording { self.pausedPlayers = players }
                else if !players.isEmpty { SystemIntegration.resumeMedia(players) }
                // Uma vez por sessão: avisa como liberar a pausa no Chrome.
                if chromeBlocked && !self.warnedChromeBlocked {
                    self.warnedChromeBlocked = true
                    // Na bolha também: quem dita no Chrome não está vendo a janela do Oruri.
                    self.state.showHUD(T("Chrome didn't pause · see Settings › Dictation"), seconds: 8)
                    self.state.showToast(T("To pause videos in Chrome, turn on View › Developer › Allow JavaScript from Apple Events in Chrome."))
                }
            }
        }
        // Com o Ollama, já carrega o modelo enquanto você fala (frio, ele leva ~20 s para responder).
        if s.usesOllama {
            LLMCleanup.warmUpOllama(endpoint: s.ollamaEndpoint, model: s.ollamaModel)
        }
    }

    func stop() {
        guard state.phase == .recording else { return }
        resumeMedia()
        guard let result = recorder.stop() else { state.phase = .idle; return }
        state.audioLevel = 0
        if result.duration < Self.minimumSeconds {
            try? FileManager.default.removeItem(at: result.url)
            state.phase = .idle
            return
        }
        state.phase = .transcribing
        let target = Delivery.frontmostBundleID
        Task {
            await process(audioURL: result.url, duration: result.duration, source: .dictation,
                          fileName: nil, targetBundleID: target)
            state.phase = .idle
        }
    }

    func cancel() {
        guard state.phase == .recording else { return }
        recorder.cancel()
        resumeMedia()
        state.audioLevel = 0
        state.phase = .idle
    }

    private func resumeMedia() {
        if !pausedPlayers.isEmpty { SystemIntegration.resumeMedia(pausedPlayers); pausedPlayers = [] }
    }

    // MARK: Arquivos arrastados

    static let supportedExtensions: Set<String> = ["wav", "mp3", "m4a", "aac", "aiff", "aif", "caf", "flac",
                                                   "mp4", "mov", "m4v", "ogg"]

    func enqueue(files: [URL]) {
        let accepted = files.filter { Self.supportedExtensions.contains($0.pathExtension.lowercased()) }
        if accepted.count < files.count { state.showToast(T("Some files were skipped: unsupported format.")) }
        fileQueue.append(contentsOf: accepted)
        state.queuedFiles = fileQueue.count
        if !processingFiles { Task { await drainQueue() } }
    }

    private func drainQueue() async {
        processingFiles = true
        while !fileQueue.isEmpty {
            let file = fileQueue.removeFirst()
            state.queuedFiles = fileQueue.count + 1
            do {
                let prepared = try await Transcriber.prepareAudio(from: file)
                await process(audioURL: prepared.url, duration: prepared.duration, source: .file,
                              fileName: file.lastPathComponent, targetBundleID: nil)
            } catch {
                state.recordings.insert(Recording(date: .now, text: "", duration: 0, status: .failed, source: .file,
                                                  fileName: file.lastPathComponent, error: error.localizedDescription), at: 0)
            }
        }
        state.queuedFiles = 0
        processingFiles = false
    }

    // MARK: Retentativa

    func retry(_ recording: Recording) {
        guard let url = Store.audioURL(for: recording), FileManager.default.fileExists(atPath: url.path) else {
            state.showToast(T("The audio for this recording is no longer on disk."))
            return
        }
        state.recordings.removeAll { $0.id == recording.id }
        Task {
            await process(audioURL: url, duration: recording.duration, source: recording.source,
                          fileName: recording.fileName, targetBundleID: nil, date: recording.date)
        }
    }

    // MARK: Pipeline

    private func process(audioURL: URL, duration: TimeInterval, source: Recording.Source, fileName: String?,
                         targetBundleID: String?, date: Date = .now) async {
        let s = state.settings
        var recording = Recording(date: date, text: "", duration: duration, status: .processing, source: source,
                                  fileName: fileName, audioFile: audioURL.lastPathComponent)
        state.recordings.insert(recording, at: 0)

        do {
            if s.suppressBlankAudio && SilenceDetector.isSilent(audioURL) { throw TranscriptionError.emptyResult }
            let provider = TranscriptionProvider(rawValue: s.engine) ?? .apple
            let raw = try await Transcriber.transcribe(TranscriptionRequest(
                audioURL: audioURL, provider: provider, model: s.activeModel, languageName: s.transcriptionLanguage,
                vocabulary: s.dictionaryEnabled ? state.dictionary.map(\.spelling) : []))

            var text = TextPipeline.process(raw, settings: s, dictionary: state.dictionary)

            let verbatim = s.verbatimInAI && targetBundleID.map(LLMCleanup.verbatimBundleIDs.contains) == true
            if s.llmCleanup && !verbatim {
                do {
                    text = try await LLMCleanup.clean(text, settings: s)
                } catch {
                    state.showToast(error.localizedDescription) // segue com o texto sem limpeza
                }
            }
            if s.addSpaceAfterSentence, let last = text.last, ".?!".contains(last), source == .dictation {
                text += " "
            }

            recording.text = text
            recording.rawText = raw
            recording.status = .done
            update(recording)

            if source == .dictation {
                let outcome = Delivery.deliver(text, settings: s, longRecording: duration > Self.longRecordingSeconds)
                if outcome == .copiedOnly {
                    if Delivery.isAccessibilityTrusted {
                        state.showHUD(T("Copied · ⌘V"))
                    } else {
                        state.showHUD(T("Copied · ⌘V · Allow Accessibility to paste"), seconds: 6)
                        if !askedForAccessibility {
                            askedForAccessibility = true
                            Delivery.requestAccessibility()
                        }
                    }
                    state.showToast(T("Copied — press ⌘V to paste"))
                }
            }
            if s.postHookEnabled {
                if SystemIntegration.isHookApproved(s.postHookCommand, approved: Keychain.get(SystemIntegration.hookApprovalAccount)) {
                    SystemIntegration.runPostHook(command: s.postHookCommand, recording: recording)
                } else {
                    state.showToast(T("The post-record command changed outside Oruri, so it didn't run. Review it in Settings › Advanced."))
                }
            }
        } catch TranscriptionError.emptyResult {
            state.recordings.removeAll { $0.id == recording.id }
            Store.deleteAudio(for: recording)
            if !s.suppressBlankAudio || source == .file { state.showToast(T("No speech detected")) }
            return
        } catch {
            recording.status = .failed
            recording.error = error.localizedDescription
            update(recording)
            state.showToast(T("Transcription failed: %@", error.localizedDescription))
        }

        // Sem histórico salvo: nada fica em disco além do necessário para colar.
        if !s.saveHistory && recording.status == .done { Store.deleteAudio(for: recording); clearAudioRef(recording.id) }
        applyRetention()
    }

    private func update(_ recording: Recording) {
        if let i = state.recordings.firstIndex(where: { $0.id == recording.id }) {
            state.recordings[i] = recording
        }
    }

    private func clearAudioRef(_ id: UUID) {
        if let i = state.recordings.firstIndex(where: { $0.id == id }) { state.recordings[i].audioFile = nil }
    }

    /// Aplica "Limit number of recordings" e "Delete old recordings". Nunca apaga o que ainda está processando.
    func applyRetention() {
        let s = state.settings
        var items = state.recordings
        var removed: [Recording] = []
        if s.deleteOld {
            let cutoff = Date().addingTimeInterval(-Double(s.deleteAfterDays) * 86_400)
            removed += items.filter { $0.date < cutoff && $0.status != .processing }
            items.removeAll { $0.date < cutoff && $0.status != .processing }
        }
        if s.limitRecordings && items.count > s.keepAtMost {
            let overflow = items.suffix(from: s.keepAtMost).filter { $0.status != .processing }
            removed += overflow
            items.removeAll { r in overflow.contains { $0.id == r.id } }
        }
        guard !removed.isEmpty else { return }
        removed.forEach(Store.deleteAudio)
        state.recordings = items
    }

    func delete(_ recording: Recording) {
        Store.deleteAudio(for: recording)
        state.recordings.removeAll { $0.id == recording.id }
    }

    func deleteAll() {
        state.recordings.filter { $0.status != .processing }.forEach(Store.deleteAudio)
        state.recordings.removeAll { $0.status != .processing }
    }
}
