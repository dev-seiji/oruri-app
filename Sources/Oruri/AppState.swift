import SwiftUI
import Observation

enum MainTab: String, CaseIterable, Identifiable {
    case home = "Home"
    case dictionary = "Dictionary"
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: "house"
        case .dictionary: "character.book.closed"
        }
    }
}

enum SettingsPane: String, CaseIterable, Identifiable {
    case dictation = "Dictation"
    case models = "Models"
    case usage = "Usage"
    case output = "Output"
    case historyPrivacy = "History & Privacy"
    case advanced = "Advanced"
    case help = "Help"
    case updates = "Updates"
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dictation: "slider.horizontal.3"
        case .models: "cpu"
        case .usage: "chart.bar"
        case .output: "text.bubble"
        case .historyPrivacy: "clock.arrow.circlepath"
        case .advanced: "gearshape"
        case .help: "questionmark.circle"
        case .updates: "sparkles"
        }
    }
}

struct DictionaryEntry: Identifiable, Hashable, Codable {
    var id = UUID()
    var spelling: String
    var heardAs: String
}

struct Recording: Identifiable, Hashable, Codable {
    enum Status: String, Codable { case processing, done, failed }
    enum Source: String, Codable { case dictation, file }

    var id = UUID()
    var date: Date
    var text: String
    /// O que o reconhecedor devolveu, antes de qualquer tratamento (para comparar com `text`).
    var rawText: String? = nil
    var duration: TimeInterval
    var status: Status = .done
    var source: Source = .dictation
    /// Nome do arquivo arrastado (só para `source == .file`).
    var fileName: String? = nil
    /// Caminho do áudio salvo, relativo à pasta de gravações.
    var audioFile: String? = nil
    var error: String? = nil
}

/// Tudo o que o usuário configura. Salvo em UserDefaults como JSON.
struct Settings: Codable, Equatable {
    // Dictation
    var triggers: [String] = ["Fn"]
    var holdToRecord = true
    var handsFree = true
    var playSound = false
    var pauseMedia = false
    var microphone = "System Default"

    // Models
    var engine = TranscriptionProvider.apple.rawValue
    var activeModel = TranscriptionProvider.apple.defaultModel

    // Output
    var transcriptionLanguage = "Portuguese"
    var numberFormatting = "Smart"
    var removeFillers = false
    var llmCleanup = false
    var ollamaEndpoint = "http://localhost:11434"
    var ollamaModel = "llama3.2"
    var smartFormatting = false
    var spokenEdits = false
    var dictionaryEnabled = true
    var customDictionary = true
    var fixSoundAlikes = true
    var copyToClipboard = true
    var autoPaste = true
    var pasteInsteadOfTyping = true
    var notifyNoPasteTarget = true
    var suppressBlankAudio = true
    var addSpaceAfterSentence = true

    // History & Privacy
    var saveHistory = true
    var limitRecordings = false
    var keepAtMost = 200
    var deleteOld = false
    var deleteAfterDays = 30

    // Advanced
    var appearance = AppearanceMode.system.rawValue
    /// Idioma da interface: sempre abre em inglês até a pessoa escolher outro (Settings › Advanced).
    var interfaceLanguage = AppLanguage.en.rawValue
    var launchAtLogin = false
    var startInMenuBar = false
    var verbatimInAI = true
    var holdLongRecordings = true
    var postHookEnabled = false
    var postHookCommand = ""
}

/// Informações do app lidas do Info.plist.
enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.6.2"
    }

    /// E-mail de suporte, mostrado em Settings › Help › Contact.
    static let supportEmail = "oruri.app@gmail.com"

    /// Lista de espera do Oruri Pro. Sem link, a janela Pro não mostra o botão.
    static let waitlistURL: URL? = URL(string: "https://tally.so/r/DqK4ZN")
}

/// Fase do ditado em andamento (mostrada no indicador flutuante).
enum DictationPhase: Equatable {
    case idle, recording, transcribing
}

@MainActor
@Observable
final class AppState {
    var selectedTab: MainTab = .home
    var showSettings = false
    var settingsPane: SettingsPane = .dictation
    var showPro = false

    var phase: DictationPhase = .idle
    var isRecording: Bool { phase == .recording }
    /// Nível do microfone (0…1) para a forma de onda do indicador.
    var audioLevel: Float = 0
    /// Mensagem curta mostrada como aviso ("Copied — press ⌘V to paste", erros…).
    var toast: String?
    /// Aviso mostrado na bolha flutuante, visível mesmo com outro app na frente.
    var hud: String?
    /// Ícone do app que estava na frente quando o ditado começou (aparece na bolha).
    var dictationAppIcon: NSImage?

    var historySearch = ""
    var recordings: [Recording] = [] { didSet { Store.saveHistory(recordings, enabled: settings.saveHistory) } }
    var dictionary: [DictionaryEntry] = [] { didSet { Store.saveDictionary(dictionary) } }
    var settings = Settings() {
        didSet {
            if settings != oldValue { Store.saveSettings(settings) }
            Localizer.shared.language = AppLanguage(rawValue: settings.interfaceLanguage) ?? .en
        }
    }
    var groqUsage = GroqUsage() { didSet { Store.saveGroqUsage(groqUsage) } }

    /// Aviso da Home: algum limite grátis da Groq com 15% ou menos sobrando, com a Groq em uso.
    /// Situação do Ollama (atualizada pelo AppDelegate enquanto a limpeza usa ele).
    var ollamaStatus: OllamaStatus = .unknown

    var ollamaWarning: String? {
        OllamaService.warning(cleanupOn: settings.llmCleanup, status: ollamaStatus)
    }

    /// Confere o Ollama agora (ao abrir, ao mudar as opções e de tempos em tempos).
    func refreshOllamaStatus() {
        let s = settings
        guard s.llmCleanup else { ollamaStatus = .unknown; return }
        Task { @MainActor in
            let status = await OllamaService.check(endpoint: s.ollamaEndpoint)
            if self.ollamaStatus != status { self.ollamaStatus = status }
        }
    }

    var groqLimitWarning: String? {
        guard settings.engine == TranscriptionProvider.groq.rawValue else { return nil }
        let t = groqUsage.tightest
        guard t.fraction >= GroqLimits.warningFraction else { return nil }
        let left = Int(((1 - t.fraction) * 100).rounded(.down))
        switch (t.name, left <= 0) {
        case ("day", true): return T("Groq free limit reached for today's audio")
        case ("hour", true): return T("Groq free limit reached for this hour's audio")
        case (_, true): return T("Groq free limit reached for today's requests")
        case ("day", false): return T("Groq free limit almost used: %ld%% of today's audio left", left)
        case ("hour", false): return T("Groq free limit almost used: %ld%% of this hour's audio left", left)
        default: return T("Groq free limit almost used: %ld%% of today's requests left", left)
        }
    }

    /// Fila de arquivos arrastados aguardando transcrição.
    var queuedFiles = 0

    /// Ligado pelo AppDelegate: quem executa gravação/transcrição de verdade.
    weak var dictation: DictationController?

    init() {
        settings = Store.loadSettings()
        Localizer.shared.language = AppLanguage(rawValue: settings.interfaceLanguage) ?? .en
        dictionary = Store.loadDictionary()
        recordings = Store.loadHistory()
        groqUsage = Store.loadGroqUsage()
        Transcriber.onGroqUsage = { [weak self] seconds, model, remaining, limit in
            self?.groqUsage.record(seconds: seconds, model: model, remaining: remaining, limit: limit)
        }
    }

    var filteredRecordings: [Recording] {
        guard !historySearch.isEmpty else { return recordings }
        return recordings.filter {
            $0.text.localizedCaseInsensitiveContains(historySearch)
                || ($0.fileName?.localizedCaseInsensitiveContains(historySearch) ?? false)
        }
    }

    var dictatedWords: Int {
        recordings.filter { $0.status == .done }.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count }
    }
    var dictationSeconds: Int { Int(recordings.filter { $0.status == .done }.reduce(0) { $0 + $1.duration }) }
    /// Tempo economizado: digitar a ~40 palavras/min menos o tempo falando.
    var secondsSaved: Int { max(0, dictatedWords * 60 / 40 - dictationSeconds) }

    func toggleRecording() {
        if let dictation { dictation.toggle() }
    }

    func openSettings(_ pane: SettingsPane = .dictation) {
        settingsPane = pane
        showSettings = true
    }

    func showHUD(_ message: String, seconds: Double = 4) {
        hud = message
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            if self?.hud == message { self?.hud = nil }
        }
    }

    func showToast(_ message: String) {
        toast = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            if self?.toast == message { self?.toast = nil }
        }
    }
}
