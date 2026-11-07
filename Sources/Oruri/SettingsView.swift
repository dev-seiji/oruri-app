import AVFoundation
import SwiftUI

/// Settings como gaveta à direita da janela principal: cada aba é uma seção em sanfona
/// que mostra um resumo do que está ligado e abre ao clicar.
struct SettingsView: View {
    @Environment(AppState.self) private var state
    @LocalState private var search = ""
    @LocalState private var open: SettingsPane? = nil

    private var panes: [SettingsPane] {
        SettingsPane.allCases.filter { search.isEmpty || T($0.rawValue).localizedCaseInsensitiveContains(search) || $0.rawValue.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(T("Settings"))
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.primaryText)
                Spacer()
                Button { state.showSettings = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.secondaryText)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Theme.card))
                        .overlay(Circle().stroke(Theme.cardBorder))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .help(T("Close"))
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.tertiaryText)
                TextField(T("Search settings"), text: $search).textFieldStyle(.plain)
            }
            .font(.system(size: 12.5))
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Capsule().fill(Theme.card))
            .overlay(Capsule().stroke(Theme.cardBorder))
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 12)

            Rectangle().fill(Theme.divider).frame(height: 1)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(panes) { pane in
                            SettingsAccordion(pane: pane, isOpen: open == pane) {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    open = open == pane ? nil : pane
                                    if let open { state.settingsPane = open }
                                }
                            }
                            .id(pane)
                        }
                    }
                    .padding(.bottom, 16)
                }
                .onAppear {
                    open = state.settingsPane
                    DispatchQueue.main.async { proxy.scrollTo(state.settingsPane, anchor: .top) }
                }
                .onChange(of: state.settingsPane) { _, pane in
                    open = pane
                    withAnimation { proxy.scrollTo(pane, anchor: .top) }
                }
            }

            Rectangle().fill(Theme.divider).frame(height: 1)
            HStack {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 16, height: 16)
                Text(T("Oruri"))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
                Text("v\(AppInfo.version)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.tertiaryText)
            }
            .padding(.horizontal, 18)
            .frame(height: 36)
        }
        .frame(maxHeight: .infinity)
        .background(Theme.settingsBackground)
    }
}

/// Uma aba de Settings dentro da gaveta: cabeçalho com ícone, nome e resumo; conteúdo quando aberta.
struct SettingsAccordion: View {
    @Environment(AppState.self) private var state
    let pane: SettingsPane
    let isOpen: Bool
    let toggle: () -> Void
    @LocalState private var hovering = false

    private var summary: String {
        let s = state.settings
        switch pane {
        case .dictation: return ComboShortcut.displayName(s.triggers.first ?? "Fn")
        case .models: return (TranscriptionProvider(rawValue: s.engine) ?? .apple).title
        case .output: return T(s.transcriptionLanguage)
        case .historyPrivacy: return T(s.saveHistory ? "History on" : "History off")
        case .advanced: return (AppearanceMode(rawValue: s.appearance) ?? .system).shortTitle
        case .usage:
            let t = state.groqUsage.tightest
            return state.groqUsage.entries.isEmpty ? T("Free plan") : T("Groq · %ld%% used", Int((t.fraction * 100).rounded()))
        case .help: return T("FAQ & contact")
        case .updates: return "v\(AppInfo.version)"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 11) {
                    Image(systemName: pane.icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 28, height: 28)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.accentSoft))
                    Text(T(pane.rawValue))
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(isOpen ? Theme.brandDeep : Theme.primaryText)
                    Spacer()
                    if !isOpen {
                        Text(summary)
                            .transition(.opacity)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.tertiaryText)
                            .lineLimit(1)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.tertiaryText)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                .padding(.horizontal, 18)
                .frame(height: 50)
                // Fundo opaco e por cima: ao abrir/fechar, o conteúdo desliza por baixo do título.
                .background(hovering && !isOpen ? Theme.statsBackground : Theme.settingsBackground)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .zIndex(1)

            if isOpen {
                VStack(alignment: .leading, spacing: 18) {
                    switch pane {
                    case .dictation: DictationPane()
                    case .models: ModelsPane()
                    case .usage: UsagePane()
                    case .output: OutputPane()
                    case .historyPrivacy: HistoryPrivacyPane()
                    case .advanced: AdvancedPane()
                    case .help: HelpPane()
                    case .updates: UpdatesPane()
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 4)
                .padding(.bottom, 20)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Rectangle().fill(Theme.divider).frame(height: 1)
        }
        .clipped()
    }
}

// MARK: - Dictation

struct DictationPane: View {
    @Environment(AppState.self) private var state
    @LocalState private var micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @LocalState private var axGranted = Delivery.isAccessibilityTrusted
    @LocalState private var devices: [AudioRecorder.InputDevice] = AudioRecorder.inputDevices()
    @LocalState private var recordingCombo = false

    var body: some View {
        @Bindable var state = state
        SettingsSection("Permissions") {
            SettingsRow(title: "Microphone", subtitle: "To hear your dictation.") {
                permissionStatus(micGranted) {
                    AVCaptureDevice.requestAccess(for: .audio) { ok in DispatchQueue.main.async { micGranted = ok } }
                }
            }
            SettingsRow(title: "Accessibility", subtitle: "To paste text into other apps and watch the recording shortcut.") {
                permissionStatus(axGranted) {
                    Delivery.requestAccessibility()
                    Delivery.openAccessibilitySettings()
                }
            }
            if !axGranted {
                Text(T("Already on but pasting doesn't work? Remove Oruri from Privacy & Security › Accessibility, add it back, then relaunch."))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            let ax = Delivery.isAccessibilityTrusted
            if ax && !axGranted { state.dictation?.restartHotkeys() }
            axGranted = ax
        }

        SettingsSection("Trigger") {
            VStack(alignment: .leading, spacing: 8) {
                Text(T("Recording trigger")).font(.system(size: 13))
                Text(T("Pick one or more keys. Hold to talk, or double-tap for hands-free."))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                ForEach(state.settings.triggers, id: \.self) { trigger in
                    HStack {
                        KeyCap(text: ComboShortcut.displayName(trigger))
                        Spacer()
                        Button { state.settings.triggers.removeAll { $0 == trigger } } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.tertiaryText)
                        }
                        .buttonStyle(.plain)
                        .help(T("Remove this trigger"))
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 30)
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.cardBorder))
                }
                if recordingCombo {
                    ComboRecorderRow(onSave: { combo in
                        addTrigger(combo.encoded)
                        recordingCombo = false
                    }, onCancel: { recordingCombo = false })
                    Text(T("Any key works except Esc, F1–F12, Backspace and Enter. Caps Lock works as on/off (tap to start, tap to stop) and combines only with ⌃ ⌥ ⇧ ⌘ fn, not letters."))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Menu {
                    Button(T("Combined shortcut…")) { recordingCombo = true }
                    Divider()
                    // Primeiro a tecla; depois, se quiser, o lado (padrão: qualquer lado).
                    ForEach(HotkeyMonitor.simpleKeys, id: \.name) { key in
                        if key.left == nil {
                            Button(key.name) { addTrigger(key.name) }
                        } else {
                            Menu(key.name) {
                                Button(T("Either side")) { addTrigger(key.name) }
                                Button(T("Left")) { addTrigger("Left \(key.name)") }
                                Button(T("Right")) { addTrigger("Right \(key.name)") }
                            }
                        }
                    }
                } label: {
                    Label(T("Add another"), systemImage: "plus").font(.system(size: 12))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.cardBorder, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
            }
            SettingsRow(title: "Cancel shortcut", subtitle: "Discards the recording.") {
                Text(T("Esc")).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.secondaryText)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.card))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.cardBorder))
            }
            ToggleRow(title: "Hold to record", subtitle: "Hold the shortcut to record, release to stop", isOn: $state.settings.holdToRecord)
            ToggleRow(title: "Hands-free mode", subtitle: "Double-press the shortcut to lock recording on; press again to stop", isOn: $state.settings.handsFree)
        }

        SettingsSection("While recording") {
            ToggleRow(title: "Play sound when recording starts", isOn: $state.settings.playSound)
            ToggleRow(title: "Pause media during recording", subtitle: "Pauses Spotify, Music or videos playing in Chrome and resumes them afterwards. Nothing happens if nothing is playing. For Chrome, turn on View › Developer › Allow JavaScript from Apple Events once.", isOn: $state.settings.pauseMedia)
            if state.settings.pauseMedia { ChromeMediaRow().padding(.leading, 12) }
        }

        SettingsSection("Input") {
            SettingsRow(title: "Microphone", subtitle: "System Default follows the system input — switch headsets and it follows") {
                Picker("", selection: $state.settings.microphone) {
                    Text(T("System Default")).tag("System Default")
                    ForEach(devices) { Text($0.name).tag($0.uid) }
                }
                .labelsHidden()
                .frame(width: 200)
                .onAppear { devices = AudioRecorder.inputDevices() }
            }
        }
    }

    private func addTrigger(_ name: String) {
        if !state.settings.triggers.contains(name) { state.settings.triggers.append(name) }
    }

    @ViewBuilder
    private func permissionStatus(_ granted: Bool, request: @escaping () -> Void) -> some View {
        if granted { GrantedLabel() }
        else { SmallBorderedButton(title: "Grant Access", action: request) }
    }
}

// MARK: - Models

struct ModelsPane: View {
    @Environment(AppState.self) private var state

    private var provider: TranscriptionProvider { TranscriptionProvider(rawValue: state.settings.engine) ?? .apple }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(TranscriptionProvider.allCases) { p in
                EngineCard(title: p.title, subtitle: p.subtitle, isSelected: provider == p) {
                    state.settings.engine = p.rawValue
                    state.settings.activeModel = p.defaultModel
                }
            }
        }

        SettingsSection(T("%@ models", provider.title)) {
            ForEach(provider.models, id: \.id) { model in
                let active = state.settings.activeModel == model.id
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(T(model.id)).font(.system(size: 12, weight: .semibold))
                        Text(T(model.detail)).font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
                    }
                    Spacer()
                    if active {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 15)).foregroundStyle(Theme.success)
                    } else {
                        SmallBorderedButton(title: "Select") { state.settings.activeModel = model.id }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 9).fill(active ? Theme.accentSoft : Theme.settingsBackground))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(active ? Theme.accent.opacity(0.5) : Theme.cardBorder))
            }
        }

        if provider.isCloud {
            SettingsSection("API key") {
                APIKeyField(account: provider.keychainAccount, placeholder: T("%@ API key", provider.rawValue), getKeyURL: provider.keyURL)
                Label(T("Audio is sent to %@'s servers — this engine is not on-device.", provider.rawValue), systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
            }
        } else {
            SettingsSection("On-device") {
                Text(T("Uses Apple's speech recognizer. Audio stays on this Mac when the language supports on-device recognition. The first use asks for Speech Recognition permission."))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        SettingsSection("Storage") {
            SettingsRow(title: "Recordings directory", subtitle: Store.recordingsDirectory.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")) {
                SmallBorderedButton(title: "Open in Finder") { NSWorkspace.shared.open(Store.recordingsDirectory) }
            }
        }
    }
}

/// Campo de chave de API salvo no Keychain.
struct APIKeyField: View {
    let account: String
    let placeholder: String
    var getKeyURL: URL?
    @LocalState private var value = ""
    @LocalState private var saved = false

    var body: some View {
        HStack(spacing: 8) {
            SecureField(T(placeholder), text: $value)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
            Button(T(saved ? "Saved" : "Save"), action: save)
                .disabled(value.isEmpty)
            if let getKeyURL {
                Button(T("Get a key")) { NSWorkspace.shared.open(getKeyURL) }.buttonStyle(.link)
            }
        }
        .onAppear {
            value = Keychain.get(account) ?? ""
            saved = !value.isEmpty
        }
        .onChange(of: value) { _, _ in saved = false }
    }

    private func save() {
        Keychain.set(value.trimmingCharacters(in: .whitespacesAndNewlines), for: account)
        saved = true
    }
}

struct EngineCard: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(T(title)).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.primaryText)
                Text(T(subtitle)).font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(isSelected ? Theme.accentSoft : Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(isSelected ? Theme.accent.opacity(0.6) : Theme.cardBorder))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Output

struct OutputPane: View {
    @Environment(AppState.self) private var state
    @LocalState private var ollamaStatus = ""

    var body: some View {
        @Bindable var state = state
        SettingsSection("Language") {
            PickerRow(title: "Transcription language", options: Language.names,
                      selection: $state.settings.transcriptionLanguage, width: 130)
        }

        SettingsSection("Numbers") {
            PickerRow(title: "Number formatting", subtitle: "Spoken numbers become digits (English and Portuguese). Common idioms stay words.",
                      options: ["Off", "Smart", "Prefer digits"], selection: $state.settings.numberFormatting, width: 130)
        }

        SettingsSection("Cleanup") {
            ToggleRow(title: "Remove filler words", subtitle: "Strip um, uh, hã, né… before inserting", isOn: $state.settings.removeFillers)
            ToggleRow(title: "Clean up with an LLM", subtitle: "Fix punctuation and obvious errors after transcribing. If the result drops or invents too much, the original is kept.", isOn: $state.settings.llmCleanup)
            if state.settings.llmCleanup {
                PickerRow(title: "AI engine", subtitle: "Groq is fast and free with your Groq key, but the text goes to Groq's servers. Ollama runs on this Mac and is slower.",
                          options: ["Groq", "Ollama"], selection: $state.settings.cleanupEngine, width: 130)
                    .padding(.leading, 12)
                if state.settings.cleanupEngine == "Groq" {
                    ToggleRow(title: "Improve sentences", subtitle: "The AI may reword confusing sentences, keeping what you meant. If numbers, names or the meaning change, Oruri only fixes the text instead.",
                              isOn: $state.settings.improveWording).padding(.leading, 12)
                }
                ToggleRow(title: "Smart formatting", subtitle: "Lists become bullets; emails and messages get greeting, paragraphs and sign-off on their own lines.",
                          isOn: $state.settings.smartFormatting).padding(.leading, 12)
                ToggleRow(title: "Spoken edits", subtitle: "Say \"scratch that\" or \"quer dizer\" and only the corrected version is inserted.",
                          isOn: $state.settings.spokenEdits).padding(.leading, 12)
            }
            if state.settings.usesOllama {
                VStack(alignment: .leading, spacing: 10) {
                    OllamaStatusRow()
                    HStack {
                        TextField(T("Endpoint"), text: $state.settings.ollamaEndpoint).textFieldStyle(.roundedBorder)
                        TextField(T("Model"), text: $state.settings.ollamaModel).textFieldStyle(.roundedBorder).frame(width: 120)
                        Button(T("Test connection")) {
                            ollamaStatus = "Connecting..."
                            Task {
                                switch await LLMCleanup.testOllama(endpoint: state.settings.ollamaEndpoint, model: state.settings.ollamaModel) {
                                case .success(let msg): ollamaStatus = "✓ " + msg
                                case .failure(let err): ollamaStatus = err.localizedDescription
                                }
                            }
                        }
                    }
                    if !ollamaStatus.isEmpty {
                        Text(T(ollamaStatus)).font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
                    }
                }
                .padding(.leading, 12)
            }
        }

        SettingsSection("Dictionary") {
            ToggleRow(title: "Custom dictionary", subtitle: "Names and jargon, spelled your way", isOn: $state.settings.customDictionary)
            ToggleRow(title: "Fix sound-alikes", subtitle: "Near-miss spellings (5+ letters, not real words) are corrected to a dictionary word.",
                      isOn: $state.settings.fixSoundAlikes).padding(.leading, 12)
            SmallBorderedButton(title: "Open dictionary", icon: "character.book.closed") {
                state.selectedTab = .dictionary; state.showSettings = false
            }
            .padding(.leading, 12)
        }

        SettingsSection("Delivery") {
            ToggleRow(title: "Copy to clipboard", subtitle: "Also leave the transcription on the clipboard. When off, the previous clipboard contents are restored", isOn: $state.settings.copyToClipboard)
            ToggleRow(title: "Auto-paste transcription", subtitle: "Insert the transcription into the focused app (needs Accessibility)", isOn: $state.settings.autoPaste)
            ToggleRow(title: "Paste instead of typing", subtitle: "⌘V instead of synthetic keystrokes — helps in Electron apps and Messages", isOn: $state.settings.pasteInsteadOfTyping)
            ToggleRow(title: "Notify when no paste target", subtitle: "“Copied — press ⌘V” if no text field is focused", isOn: $state.settings.notifyNoPasteTarget)
            ToggleRow(title: "Suppress blank audio", subtitle: "Silently drop recordings with no speech", isOn: $state.settings.suppressBlankAudio)
            ToggleRow(title: "Add space after sentence", subtitle: "Useful when dictating in bursts", isOn: $state.settings.addSpaceAfterSentence)
        }
    }
}

/// Situação do Ollama em Settings › Output, com um botão para ligar sem usar o Terminal.
struct OllamaStatusRow: View {
    @Environment(AppState.self) private var state
    @LocalState private var starting = false

    var body: some View {
        let status = state.ollamaStatus
        HStack(spacing: 8) {
            Circle()
                .fill(status == .running ? Theme.success : status == .unknown ? Theme.tertiaryText : Theme.recording)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(title(status)).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.primaryText)
                Text(detail(status)).font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            switch status {
            case .stopped:
                SmallBorderedButton(title: starting ? "Starting…" : "Start Ollama", icon: "play.fill") { start() }
                    .disabled(starting)
            case .notInstalled:
                SmallBorderedButton(title: "Download Ollama", icon: "arrow.down.circle") { NSWorkspace.shared.open(OllamaService.downloadURL) }
            case .running, .unknown:
                EmptyView()
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 9).fill(Theme.settingsBackground))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.cardBorder))
        .onAppear { state.refreshOllamaStatus() }
    }

    private func title(_ status: OllamaStatus) -> String {
        switch status {
        case .running: T("Ollama is running")
        case .stopped: T("Ollama is off")
        case .notInstalled: T("Ollama isn't installed")
        case .unknown: T("Checking Ollama…")
        }
    }

    private func detail(_ status: OllamaStatus) -> String {
        switch status {
        case .running: T("AI cleanup is working.")
        case .stopped: T("AI cleanup is paused until it's on. Start it here, no Terminal needed.")
        case .notInstalled: T("Install it from ollama.com, then pull a model such as llama3.2.")
        case .unknown: T("This takes a second.")
        }
    }

    /// Liga o Ollama e confere algumas vezes até ele responder.
    private func start() {
        starting = true
        OllamaService.start()
        Task { @MainActor in
            for _ in 0..<15 {
                try? await Task.sleep(for: .seconds(1))
                state.refreshOllamaStatus()
                if state.ollamaStatus == .running { break }
            }
            starting = false
            let s = state.settings
            LLMCleanup.warmUpOllama(endpoint: s.ollamaEndpoint, model: s.ollamaModel)
        }
    }
}

/// Pausa no Chrome: mostra se ele deixa o Oruri pausar vídeos e liga a opção com um clique.
struct ChromeMediaRow: View {
    @LocalState private var access: SystemIntegration.ChromeAccess? = nil
    @LocalState private var working = false
    @LocalState private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: access == .allowed ? "checkmark.circle.fill" : "play.rectangle")
                    .foregroundStyle(access == .allowed ? Theme.success : Theme.secondaryText)
                Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.primaryText)
                Spacer(minLength: 8)
                switch access {
                case .blocked:
                    SmallBorderedButton(title: working ? "Waiting for your click…" : "Show me in Chrome", icon: "hand.point.up.left") { showMe() }
                        .disabled(working)
                case .notRunning:
                    SmallBorderedButton(title: "Check again", icon: "arrow.clockwise") { refresh() }
                case .allowed, nil:
                    EmptyView()
                }
            }
            if access == .blocked || failed {
                Text(T(failed ? "Couldn't open the menu. In Chrome, go to View › Developer › Allow JavaScript from Apple Events. You only need to do this once." : "Chrome opens with the right menu: click Allow JavaScript from Apple Events. You only need to do this once."))
                    .font(.system(size: 11))
                    .foregroundStyle(failed ? Theme.recording : Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { refresh() }
    }

    private var title: String {
        switch access {
        case .allowed: T("Chrome: videos pause too")
        case .blocked: T("Chrome: needs one setting to pause videos")
        case .notRunning: T("Chrome: open it to check")
        case nil: T("Chrome: checking…")
        }
    }

    private func refresh() {
        Task { @MainActor in access = await SystemIntegration.onMediaQueue { SystemIntegration.chromeAccess() } }
    }

    /// Abre o menu no Chrome e confere a cada 2 s, por até 1 min, se a pessoa já clicou.
    private func showMe() {
        working = true
        Task { @MainActor in
            failed = !(await SystemIntegration.onMediaQueue { SystemIntegration.showChromeJavaScriptMenu() })
            for _ in 0..<30 where !failed {
                try? await Task.sleep(for: .seconds(2))
                access = await SystemIntegration.onMediaQueue { SystemIntegration.chromeAccess() }
                if access == .allowed { break }
            }
            working = false
        }
    }
}

// MARK: - History & Privacy

struct HistoryPrivacyPane: View {
    @Environment(AppState.self) private var state
    @LocalState private var confirmDelete = false

    var body: some View {
        @Bindable var state = state
        SettingsSection("Privacy") {
            ToggleRow(title: "Save transcription history",
                      subtitle: "Off = nothing is kept on disk — history lives in memory until you quit",
                      isOn: $state.settings.saveHistory)
            SettingsRow(title: "Transcriptions directory", subtitle: Store.directory.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")) {
                SmallBorderedButton(title: "Open in Finder") { NSWorkspace.shared.open(Store.directory) }
            }
        }
        SettingsSection("Retention") {
            ToggleRow(title: "Limit number of recordings", subtitle: "Keep only the most recent recordings & transcriptions", isOn: $state.settings.limitRecordings)
            if state.settings.limitRecordings {
                Stepper(T("Keep at most %ld recordings", state.settings.keepAtMost), value: $state.settings.keepAtMost, in: 10...5000, step: 10)
                    .font(.system(size: 12)).padding(.leading, 12)
            }
            ToggleRow(title: "Delete old recordings", subtitle: "Automatically remove recordings older than the chosen age", isOn: $state.settings.deleteOld)
            if state.settings.deleteOld {
                Stepper(T("Delete after %ld days", state.settings.deleteAfterDays), value: $state.settings.deleteAfterDays, in: 1...365)
                    .font(.system(size: 12)).padding(.leading, 12)
            }
            Text(T("Both limits combine — whichever is hit first wins. Recordings still being processed are never deleted."))
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
        }
        SettingsSection {
            HStack {
                Spacer()
                Button(T("Delete All Recordings"), role: .destructive) { confirmDelete = true }
            }
        }
        .confirmationDialog(T("Delete all recordings?"), isPresented: $confirmDelete) {
            Button(T("Delete All"), role: .destructive) { state.dictation?.deleteAll() }
        } message: {
            Text(T("This removes every transcription and its audio. This action cannot be undone."))
        }
    }
}

// MARK: - Advanced

struct AdvancedPane: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var state = state
        SettingsSection("App") {
            SettingsRow(title: "Appearance", subtitle: "Light, dark, or follow the Mac's setting.") {
                Picker("", selection: $state.settings.appearance) {
                    ForEach(AppearanceMode.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 230)
            }
            SettingsRow(title: "Language", subtitle: "The language of Oruri's screens. Dictation keeps its own language in Output.") {
                Picker("", selection: $state.settings.interfaceLanguage) {
                    ForEach(AppLanguage.allCases) { Text($0.nativeName).tag($0.rawValue) }
                }
                .labelsHidden()
                .frame(width: 130)
            }
            ToggleRow(title: "Launch at login", subtitle: "Start automatically when you log in.", isOn: $state.settings.launchAtLogin)
            ToggleRow(title: "Start in the menu bar", subtitle: "Launch without the main window — open it from the menu bar icon.", isOn: $state.settings.startInMenuBar)
        }
        SettingsSection("Safeguards") {
            ToggleRow(title: "Verbatim in AI & terminal apps", subtitle: "Skip LLM cleanup in AI chats and terminals so prompts arrive word for word.", isOn: $state.settings.verbatimInAI)
            ToggleRow(title: "Hold very long recordings", subtitle: "Recordings over 5 minutes are copied instead of pasted.", isOn: $state.settings.holdLongRecordings)
        }
        SettingsSection("Post-record hook") {
            ToggleRow(title: "Run a command after each transcription", subtitle: "Runs via /bin/sh -c in the background.", isOn: $state.settings.postHookEnabled)
            if state.settings.postHookEnabled {
                TextField(T("echo \"$ORURI_TEXT\" >> ~/dictations.txt"), text: $state.settings.postHookCommand)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                Text(T("Available: ORURI_TEXT, ORURI_AUDIO_PATH, ORURI_TIMESTAMP, ORURI_DURATION (also as JSON on stdin)."))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        SettingsSection("Debug") {
            SettingsRow(title: "Onboarding", subtitle: "Reset the first-run flag and walk through setup again.") {
                SmallBorderedButton(title: "Show Onboarding", icon: "arrow.counterclockwise") {
                    UserDefaults.standard.set(false, forKey: OnboardingKeys.completed)
                    state.showSettings = false
                    openWindow(id: "onboarding")
                }
            }
        }
    }
}

// MARK: - Usage

/// Uso de cada serviço de IA, no estilo das páginas de uso do Claude e do ChatGPT:
/// uma barrinha por limite e o gasto do mês em dólar. Só a Groq é contada por enquanto.
struct UsagePane: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let g = state.groqUsage
        let r = g.dayRequests
        let month = g.thisMonth
        let monthSeconds = month.reduce(0) { $0 + $1.seconds }

        SettingsSection("Transcription") {
            UsageProviderHeader(name: "Groq", plan: "FREE PLAN",
                                status: state.settings.engine == TranscriptionProvider.groq.rawValue ? "In use" : "Not selected")
            UsageBar(title: "Audio · last 24 hours",
                     detail: T("%@ of 8 h", UsageFormat.duration(g.seconds(since: .now.addingTimeInterval(-86_400)))),
                     fraction: g.dayAudioFraction)
            UsageBar(title: "Audio · last hour",
                     detail: T("%@ of 2 h", UsageFormat.duration(g.seconds(since: .now.addingTimeInterval(-3_600)))),
                     fraction: g.hourAudioFraction)
            UsageBar(title: "Requests · daily allowance",
                     detail: T("%@ of %@", r.used.formatted(), r.limit.formatted()),
                     fraction: g.dayRequestsFraction)
            if !(g.cleanups ?? []).isEmpty {
                let c = g.cleanupRequestsUsed()
                UsageBar(title: "AI cleanup requests · daily allowance",
                         detail: T("%@ of %@", c.used.formatted(), c.limit.formatted()),
                         fraction: g.cleanupRequestsFraction)
            }
            Text(T("Groq counts requests as an allowance that refills: each one comes back about 43 seconds later. That's why it can be almost empty even after many requests this month."))
                .font(.system(size: 11))
                .foregroundStyle(Theme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
            Rectangle().fill(Theme.divider).frame(height: 1)
            UsageMonthRow(detail: g.cleanupsThisMonth > 0
                              ? T("%@ of audio · %ld requests · %ld AI cleanup requests", UsageFormat.duration(monthSeconds), month.count, g.cleanupsThisMonth)
                              : T("%@ of audio · %ld requests", UsageFormat.duration(monthSeconds), month.count),
                          amount: "$0.00",
                          note: T("Free plan. On the paid plan this would be about %@.", UsageFormat.dollars(g.monthCost)))
        }

        VStack(alignment: .leading, spacing: 10) {
            Text(T("Counted on this Mac. When 15% or less of a Groq limit is left, a warning appears on Home. Ollama runs on this Mac and has no limit."))
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                UsageLimitsButton(title: "Groq limits", url: "https://console.groq.com/settings/limits")
            }
        }
        .padding(.horizontal, 2)
    }
}

/// Abre a página oficial de limites do serviço no navegador.
struct UsageLimitsButton: View {
    let title: String
    let url: String

    var body: some View {
        SmallBorderedButton(title: title, icon: "arrow.up.right") {
            if let link = URL(string: url) { NSWorkspace.shared.open(link) }
        }
    }
}

struct UsageProviderHeader: View {
    let name: String
    let plan: String
    let status: String

    var body: some View {
        HStack(spacing: 8) {
            Text(name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.primaryText)
            Badge(text: plan)
            Spacer()
            Text(T(status))
                .font(.system(size: 11))
                .foregroundStyle(status == "In use" ? Theme.accent : Theme.tertiaryText)
        }
    }
}

/// Uma barrinha de limite: nome, quanto foi usado e a porcentagem; fica vermelha a partir de 85%.
struct UsageBar: View {
    let title: String
    let detail: String
    let fraction: Double

    var body: some View {
        let f = min(max(fraction, 0), 1)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(T(title))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.primaryText)
                Spacer()
                Text("\(detail) · \(Int((f * 100).rounded()))%")
                    .font(.system(size: 11.5))
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondaryText)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.statsBackground)
                    Capsule()
                        .fill(f >= GroqLimits.warningFraction ? Theme.recording : Theme.accent)
                        .frame(width: f > 0 ? max(6, geo.size.width * f) : 0)
                }
            }
            .frame(height: 8)
            .overlay(Capsule().stroke(Theme.statsBorder.opacity(0.6)))
            .animation(.easeOut(duration: 0.4), value: f)
        }
    }
}

struct UsageMonthRow: View {
    let detail: String
    let amount: String
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(T("This month"))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.primaryText)
                Spacer()
                Text(amount)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.primaryText)
            }
            Text(T(detail))
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.secondaryText)
            Text(T(note))
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Help

struct HelpItem: Identifiable {
    let title: String
    let body: String
    var id: String { title }
}

/// Uma pergunta ou tópico do manual que abre e fecha com um clique.
struct HelpItemRow: View {
    let item: HelpItem
    var expanded: Bool
    @LocalState private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) { open.toggle() }
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .rotationEffect(.degrees(open || expanded ? 90 : 0))
                        .padding(.top, 3)
                    Text(T(item.title))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.primaryText)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open || expanded {
                Text(T(item.body))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .padding(.leading, 18)
            }
        }
    }
}

/// Textos da Help: perguntas frequentes (tiradas dos testes) e o manual, tela por tela.
enum HelpContent {
    static let faq: [HelpItem] = [
        HelpItem(title: "The text didn't paste into the app",
                 body: "Oruri needs Accessibility to paste. Open Settings › Dictation and check that Accessibility shows Granted. Make sure the cursor is in a text field when you release the key."),
        HelpItem(title: "Accessibility is on, but pasting still doesn't work",
                 body: "The permission may belong to an older copy of the app. In System Settings › Privacy & Security › Accessibility, remove Oruri with the minus button, add it again with the plus button, then quit and reopen Oruri."),
        HelpItem(title: "The text was only copied, not pasted",
                 body: "This happens when no text field is focused, when Accessibility is off, or when a recording is longer than 5 minutes (long recordings are only copied, on purpose). Press ⌘V to paste it."),
        HelpItem(title: "The AI didn't change my text in Claude, ChatGPT or the Terminal",
                 body: "That's verbatim mode: in AI apps and terminals the text arrives exactly as spoken, so your instructions aren't rewritten. You can turn it off in Settings › Advanced."),
        HelpItem(title: "How do I correct myself while talking?",
                 body: "Say the wrong part, a correction phrase and the right part: \"send it to Pedro, errei, to Paulo\" or \"on Thursday, quer dizer, on Friday\". You can also start a new sentence with \"Não\": \"…tomorrow, right? Não, tomorrow, the day after tomorrow.\" Only the corrected version is kept."),
        HelpItem(title: "How do I dictate numbers, percentages and versions?",
                 body: "Say them naturally: \"vinte e cinco\" becomes 25, \"cem por cento\" becomes 100% and \"zero ponto dois ponto um\" becomes 0.2.1. Choose Smart or Prefer digits in Settings › Output › Numbers."),
        HelpItem(title: "How does a shortcut with Caps Lock work?",
                 body: "Caps Lock works as on/off: tap the shortcut to start recording and tap it again to stop. With Caps Lock you can only combine ⌃ ⌥ ⇧ ⌘ fn, not letters."),
        HelpItem(title: "Which transcription engine should I use?",
                 body: "On-device is free, private and works offline. Groq is very fast and has a free plan; whisper-large-v3-turbo is the default and the quickest. Groq needs your own API key. Long files are compressed before sending, so it takes up to about 1 h 40 min per file."),
        HelpItem(title: "How do I turn Ollama on, and use it in AI apps too?",
                 body: "Turn it on in Settings › Output › AI cleanup and pick Groq (fast, in the cloud) or Ollama (on this Mac): it then cleans every text you dictate. In AI apps and terminals (Claude, ChatGPT, Terminal, Cursor) the text skips cleanup and arrives exactly as spoken. To clean those too, turn off \"Verbatim in AI & terminal apps\" in Settings › Advanced; turn it back on to keep them word for word."),
        HelpItem(title: "Why does AI cleanup sometimes leave my text as it was?",
                 body: "The AI may only tidy punctuation, capitals and spelling, and apply your spoken corrections. If it changes a number, a name, a \"not\" or a word, drops part of what you said or rewrites the sentence, Oruri keeps your original text instead, so the meaning never changes."),
        HelpItem(title: "Why does Ollama use memory while Oruri is open?",
                 body: "To answer in about a second, Oruri keeps the Ollama model loaded while it's open (around 2 GB with llama3.2). Without it, the first dictation after a while waited about 20 seconds. When you quit Oruri, the memory is freed."),
        HelpItem(title: "How do I keep Ollama running for AI cleanup?",
                 body: "Settings › Output shows whether Ollama is running. If it's off, click Start Ollama there: no Terminal needed. When Ollama is off, a warning on Home takes you to that button. If you installed it with Homebrew, it also starts with your Mac from then on."),
        HelpItem(title: "How do I know if I'm running out of a limit?",
                 body: "Open Settings › Usage: each bar shows how much you've used and turns red at 85%. When 15% or less of a limit or credit is left, a warning appears on Home. Ollama has no limit, so it isn't counted. The buttons at the bottom open the official limits page of each service."),
        HelpItem(title: "How do I change the app's language?",
                 body: "Go to Settings › Advanced › Language and pick English, Español, Português or 日本語. Oruri switches right away. This only changes the screens: the language you dictate in is set in Settings › Output › Transcription language."),
        HelpItem(title: "Where is my data stored?",
                 body: "Everything stays on this Mac: history and audio in ~/Library/Application Support/Oruri and API keys in the Keychain. Audio and text only leave the Mac if you choose Groq."),
    ]

    static let manual: [HelpItem] = [
        HelpItem(title: "Home", body: "Record with the microphone button, see your stats and search your history. Drop audio or video files here, or click the folder button at the bottom right to choose them, and they're transcribed one by one."),
        HelpItem(title: "Dictionary", body: "Add names and words so they're always spelled your way, one at a time or as a list."),
        HelpItem(title: "Settings › Dictation", body: "Permissions, your dictation keys and combined shortcuts, hold to talk, hands-free, start sound, pausing music and the microphone."),
        HelpItem(title: "Settings › Models", body: "Choose the transcription engine (On-device or Groq), the model and your API key."),
        HelpItem(title: "Settings › Usage", body: "How much of Groq's free limits you've used (audio per day and per hour, and the daily requests allowance, which refills on its own) and this month's cost in dollars. When 15% or less of any limit is left, a warning appears on Home."),
        HelpItem(title: "Settings › Output", body: "Language, numbers, filler words, AI cleanup, the dictionary and how text is delivered (paste, type, clipboard)."),
        HelpItem(title: "Settings › History & Privacy", body: "Turn history on or off, open the recordings folder, set retention limits or delete everything."),
        HelpItem(title: "Settings › Advanced", body: "Appearance, the app's language, launch at login, start in the menu bar, verbatim mode in AI apps (turn it off to let Ollama clean text there too), long recordings and the post-record command."),
        HelpItem(title: "Settings › Updates", body: "Your version and the notes of each release."),
    ]
}

struct HelpPane: View {
    @Environment(AppState.self) private var state
    @LocalState private var copied = false
    @LocalState private var query = ""

    private func matches(_ item: HelpItem) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty || T(item.title).localizedCaseInsensitiveContains(q) || T(item.body).localizedCaseInsensitiveContains(q)
    }

    private let supportEmail = AppInfo.supportEmail

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(Theme.tertiaryText)
            TextField(T("Search help"), text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.tertiaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(Capsule().fill(Theme.pillBackground))
        .overlay(Capsule().stroke(Theme.pillBorder))

        let faq = HelpContent.faq.filter(matches)
        let manual = HelpContent.manual.filter(matches)

        if faq.isEmpty && manual.isEmpty {
            Text(T("No results for \"%@\". Try other words, or email us below.", query))
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.secondaryText)
        }
        if !faq.isEmpty {
            SettingsSection("Frequently asked questions") {
                ForEach(faq) { HelpItemRow(item: $0, expanded: !query.isEmpty) }
            }
        }
        if !manual.isEmpty {
            SettingsSection("Where to find things") {
                ForEach(manual) { HelpItemRow(item: $0, expanded: !query.isEmpty) }
            }
        }

        SettingsSection("Contact") {
            Text(T("Found a bug or have an idea? Send us an email."))
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.secondaryText)
            // O e-mail fica numa linha e os botões em outra, para "Copied" nunca ser espremido pela gaveta.
            VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "envelope")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.accent)
                Text(supportEmail)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.primaryText)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            HStack(spacing: 8) {
                Button {
                    Delivery.copy(supportEmail)
                    state.showToast(T("Email copied"))
                    withAnimation(.easeOut(duration: 0.15)) { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation(.easeOut(duration: 0.2)) { copied = false }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11, weight: .semibold))
                        Text(T(copied ? "Copied" : "Copy"))
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(copied ? Theme.onAccent : Theme.accent)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(Capsule().fill(copied ? Theme.accent : Theme.accentSoft))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(T("Copy email"))
                Button {
                    if let url = URL(string: "mailto:\(supportEmail)?subject=Oruri") { NSWorkspace.shared.open(url) }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "paperplane")
                            .font(.system(size: 11, weight: .semibold))
                        Text(T("Send email"))
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(Capsule().fill(Theme.accent))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(T("Opens your email app"))
            }
            .fixedSize()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.settingsBackground))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.cardBorder))
        }
    }
}

// MARK: - Updates

struct UpdatesPane: View {
    private var version: String { AppInfo.version }

    /// Notas de versão do Oruri, da mais nova para a mais antiga.
    private let releases: [(version: String, date: String, notes: [String])] = [
        ("0.6.6", "November 2026", [
            "Settings › Usage now counts AI cleanup with Groq: its own daily allowance and the month total, and the Home warning covers it too.",
        ]),
        ("0.6.5", "November 2026", [
            "With Groq, \"Improve sentences\" lets the AI reword confusing sentences while keeping numbers, names and meaning.",
            "Groq cleanup works again: Oruri now picks a Groq model that is available.",
        ]),
        ("0.6.4", "November 2026", [
            "Long files are compressed before going to Groq, so one file can be up to about 1 h 40 min instead of 12 min.",
        ]),
        ("0.6.3", "November 2026", [
            "AI cleanup can now use Groq: much faster than Ollama, free with the same Groq key. Pick it in Settings › Output.",
        ]),
        ("0.6.2", "November 2026", [
            "When no text box is selected, the text is copied and \"Copied · ⌘V\" appears again, including in Chrome, Claude and other Electron apps.",
        ]),
        ("0.6.1", "November 2026", [
            "Settings › Help › Contact has the real support email, and the Pro window has a button to join the waitlist.",
        ]),
        ("0.6.0", "November 2026", [
            "Paid cloud AI with your own key (one transcription engine and one cleanup option) was removed. AI cleanup now runs only on Ollama, on this Mac; if you used the removed engine, the app switches to On-device.",
        ]),
        ("0.5.8", "November 2026", [
            "The buttons at the top right sit a little lower and further from the window edge.",
        ]),
        ("0.5.7", "November 2026", [
            "Pause media now also pauses videos playing in Chrome and resumes them afterwards. Settings › Dictation shows whether Chrome allows it, with a button that takes you to the one setting it needs.",
            "Security fixes: a long run of number words can no longer close the app, and Oruri is signed so other programs can't inject code into it and use its permissions.",
        ]),
        ("0.5.6", "November 2026", [
            "Behind-the-scenes cleanup: leftover options from older versions were removed. Nothing changes in how Oruri works, and your settings stay as they were.",
        ]),
        ("0.5.5", "November 2026", [
            "Settings › Usage now shows Groq's requests the way Groq counts them: a daily allowance that refills, with one request coming back about every 43 seconds.",
        ]),
        ("0.5.4", "November 2026", [
            "Settings › Output shows whether Ollama is running, with a Start Ollama button: no Terminal needed.",
            "When AI cleanup uses Ollama and it's off, a warning on Home takes you straight to that button.",
        ]),
        ("0.5.3", "November 2026", [
            "AI cleanup keeps what you said: if the AI changes a number, a name, a \"not\" or a word, or drops part of the sentence, your original text is used.",
            "Ollama no longer answers your dictation instead of cleaning it.",
        ]),
        ("0.5.2", "November 2026", [
            "Oruri Pro has a waitlist: click Pro at the top to join and hear when it's ready.",
            "Help › Contact has a Send email button that opens your email app.",
        ]),
        ("0.5.0", "November 2026", [
            "New name: Oruri, after the ōruri, a blue songbird from Japan.",
            "New blue look, a new app icon and a new menu bar icon.",
        ]),
        ("0.4.2", "October 2026", [
            "Noise, key clicks and breathing no longer turn into invented phrases.",
            "Ollama stays loaded while Oruri is open, so AI cleanup answers in about a second.",
            "Groq uses its fastest model, whisper-large-v3-turbo, by default.",
        ]),
        ("0.4.1", "October 2026", [
            "Recording starts right away: pausing Music or Spotify no longer holds up the bubble or the key.",
            "Background noise no longer counts as speech: silent recordings are dropped instead of being sent for transcription.",
        ]),
        ("0.4.0", "October 2026", [
            "Oruri now speaks Spanish, Portuguese and Japanese: pick the language in Settings › Advanced › Language. It always starts in English.",
            "Every screen switches on the spot: Home, Settings, Help, notices, the menu bar and these notes.",
            "The transcription language stays separate in Settings › Output, so you can use the app in one language and dictate in another.",
        ]),
        ("0.3.5", "October 2026", [
            "New folder button at the bottom right of Home: click it to choose audio or video files in Finder and add them to the transcription queue.",
        ]),
        ("0.3.4", "October 2026", [
            "With Ollama chosen for AI cleanup, every text you dictate is cleaned, not just long or complex ones.",
            "The safety check stays: if Ollama adds words you didn't say or drops too much, your original text is kept.",
            "New Help answer: how to turn Ollama on and how to use it in AI apps and terminals too.",
        ]),
        ("0.3.3", "October 2026", [
            "New Usage section in Settings: how much of Groq's free limits you've used, with a bar for audio per day, audio per hour and requests per day.",
            "A warning appears on Home when 15% or less of a limit is left, with a button that opens Usage.",
        ]),
        ("0.3.2", "October 2026", [
            "Help now answers common questions: paste problems, spoken corrections, numbers, Caps Lock shortcuts, engines, Ollama and where your data is stored.",
            "New Where to find things guide: what's on each screen and in each Settings section.",
            "A search field at the top of Help filters the questions and the guide as you type.",
        ]),
        ("0.3.1", "October 2026", [
            "A smaller, simpler recording bubble in the same color: just the icon of the app you're dictating into and the lines of your voice.",
            "No more cancel and stop buttons on the bubble: release the key to stop, press Esc to cancel.",
            "The bubble rises from the bottom center of the screen, just above the Dock.",
        ]),
        ("0.3.0", "October 2026", [
            "A new look: no sidebar. The microphone sits in the middle of the window, with the microphone and speech model right below it and your numbers in one line.",
            "Settings opens as a drawer on the right, and each section expands to show its options.",
            "New appearance button at the top: a sun or a moon shows the current look, and a click picks System, Light or Dark. Also in the menu bar.",
        ]),
        ("0.2.3", "October 2026", [
            "Combined shortcuts: in Settings › Dictation › Add another › Combined shortcut, press the keys together (⌃⇧ or ⌃⇧D) and they become your dictation shortcut. Hold to talk and double tap work the same.",
            "Caps Lock works as on/off: tap to start, tap again to stop. With Caps Lock, only ⌃ ⌥ ⇧ ⌘ fn can be combined.",
            "Simple keys are picked by name (Fn, Command, Option, Control, Shift), then the side if you want: left, right or either.",
        ]),
        ("0.2.2", "October 2026", [
            "Numbers with dots and commas stay together: versions like 0.2.1, decimals like 1,5 and times like 10:30 are no longer split.",
            "Spoken versions and decimals: \"zero ponto dois ponto um\" becomes 0.2.1 and \"zero point two\" becomes 0.2.",
        ]),
        ("0.2.1", "October 2026", [
            "Start in the menu bar now works: Oruri opens without its window and stays in the Dock and the menu bar. Click the Dock icon to open the window.",
        ]),
        ("0.2.0", "October 2026", [
            "Pastes into any app you can type in, including Claude, ChatGPT, Chrome and WhatsApp.",
            "Spoken corrections: say \"errei\", \"quer dizer\" or \"não, …\" and only the corrected version is kept, even after several corrections in a row.",
            "Spoken percentages become the % sign: \"100 por cento\" turns into 100%.",
        ]),
        ("0.1.0", "October 2026", [
            "Dictate anywhere: hold your key, talk and release — the text lands where you're typing.",
            "Transcription on this Mac with punctuation, or in the cloud with Groq using your own key.",
            "Spoken punctuation, filler-word removal, numbers as digits and a custom dictionary.",
        ]),
    ]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text("Oruri \(version)").font(.system(size: 13, weight: .semibold))
                Text(T("Automatic updates aren't available yet. New versions are installed by building the app again."))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }

        ForEach(releases, id: \.version) { release in
            SettingsSection(T("What's new in %@ — %@", release.version, T(release.date))) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(release.notes, id: \.self) { note in
                        HStack(alignment: .top, spacing: 8) {
                            Circle().fill(Theme.accent).frame(width: 5, height: 5).padding(.top, 6)
                            Text(T(note)).font(.system(size: 12.5)).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }
}
