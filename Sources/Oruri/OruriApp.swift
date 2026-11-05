import SwiftUI
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Fica no delegate para que o indicador (AppKit) e as cenas SwiftUI compartilhem o mesmo estado.
    let state = AppState()
    private var indicator: RecordingIndicatorController?
    private var dictation: DictationController?
    /// Confere de tempos em tempos se o Ollama está respondendo (só quando a limpeza usa ele).
    private var ollamaTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        indicator = RecordingIndicatorController(state: state)
        let dictation = DictationController(state: state)
        self.dictation = dictation
        state.dictation = dictation
        AppearanceMode(rawValue: state.settings.appearance)?.apply()
        observeSettings()
        warmUpOllamaIfUsed(state.settings)
        state.refreshOllamaStatus()
        ollamaTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.state.refreshOllamaStatus() }
        }
        // Sempre com ícone no Dock (também quando executado via `swift run`, sem bundle).
        NSApp.setActivationPolicy(.regular)
        if state.settings.startInMenuBar {
            // "Start in the menu bar": abre sem a janela; ela aparece pelo Dock ou por "Open Oruri".
            // A janela do SwiftUI é criada logo depois deste método, por isso o esconder fica para o próximo ciclo.
            DispatchQueue.main.async { [weak self] in self?.mainWindow?.orderOut(nil) }
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// A janela principal do app (cena `Window(id: "main")`).
    private var mainWindow: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("main") == true }
    }

    /// Clique no ícone do Dock sem janela visível: mostra a janela principal.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag, let window = mainWindow else { return true }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        let s = state.settings
        if s.llmCleanup {
            LLMCleanup.unloadOllama(endpoint: s.ollamaEndpoint, model: s.ollamaModel)
        }
    }

    /// Com a limpeza pelo Ollama ligada, deixa o modelo carregado desde já (e ao trocar de modelo).
    private func warmUpOllamaIfUsed(_ s: Settings) {
        guard s.llmCleanup else { return }
        LLMCleanup.warmUpOllama(endpoint: s.ollamaEndpoint, model: s.ollamaModel)
    }

    /// "Abrir com Oruri" / arrastar no ícone do Dock: entra na fila de transcrição.
    func application(_ application: NSApplication, open urls: [URL]) {
        dictation?.enqueue(files: urls)
    }

    /// Reaplica atalhos, retenção e "abrir ao iniciar sessão" quando as configurações mudam.
    private func observeSettings() {
        let before = state.settings
        withObservationTracking {
            _ = state.settings
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let after = self.state.settings
                self.dictation?.applySettings()
                if after.llmCleanup != before.llmCleanup
                    || after.ollamaModel != before.ollamaModel || after.ollamaEndpoint != before.ollamaEndpoint {
                    self.warmUpOllamaIfUsed(after)
                    self.state.refreshOllamaStatus()
                }
                if after.appearance != before.appearance { AppearanceMode(rawValue: after.appearance)?.apply() }
                if after.launchAtLogin != before.launchAtLogin { SystemIntegration.setLaunchAtLogin(after.launchAtLogin) }
                if after.limitRecordings != before.limitRecordings || after.keepAtMost != before.keepAtMost
                    || after.deleteOld != before.deleteOld || after.deleteAfterDays != before.deleteAfterDays {
                    self.dictation?.applyRetention()
                }
                self.observeSettings()
            }
        }
    }
}

@main
struct OruriApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private var state: AppState { appDelegate.state }

    var body: some Scene {
        Window("Oruri", id: "main") {
            ContentView()
                .environment(state)
                .localizedRoot()
                .frame(minWidth: 900, minHeight: 612)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 900, height: 612)
        .commands {
            CommandGroup(after: .help) {
                ShowOnboardingButton()
            }
        }

        Window("Welcome to Oruri", id: "onboarding") {
            OnboardingView()
                .environment(state)
                .localizedRoot()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarContent()
                .environment(state)
                .localizedRoot()
        } label: {
            Image(nsImage: MenuBarIcon.image(recording: state.isRecording))
        }
    }
}

/// Ícone da barra de menus: a silhueta da ōruri (imagem modelo, segue o claro/escuro do sistema).
/// Gravando, ganha uma bolinha cheia à direita.
enum MenuBarIcon {
    private static let base: NSImage? = Bundle.main.image(forResource: "MenuBarIcon")

    static func image(recording: Bool) -> NSImage {
        guard let base else {
            return NSImage(systemSymbolName: recording ? "waveform.circle.fill" : "waveform", accessibilityDescription: "Oruri")!
        }
        guard recording else { base.isTemplate = true; return base }
        let dot: CGFloat = 5, gap: CGFloat = 2
        let size = NSSize(width: base.size.width + gap + dot, height: base.size.height)
        let image = NSImage(size: size, flipped: false) { _ in
            base.draw(in: NSRect(origin: .zero, size: base.size))
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: size.width - dot, y: size.height - dot - 1, width: dot, height: dot)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}

struct MenuBarContent: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(T(state.isRecording ? "Stop Recording" : "Start Recording")) { state.toggleRecording() }
        Divider()
        Button(T("Open Oruri")) {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Menu(T("Appearance")) {
            ForEach(AppearanceMode.allCases, id: \.rawValue) { mode in
                Toggle(mode.shortTitle, isOn: Binding(
                    get: { state.settings.appearance == mode.rawValue },
                    set: { if $0 { state.settings.appearance = mode.rawValue } }))
            }
        }
        Button(T("Settings...")) {
            openWindow(id: "main")
            state.showSettings = true
            NSApp.activate(ignoringOtherApps: true)
        }
        Button(T("About & Updates…")) {
            openWindow(id: "main")
            state.openSettings(.updates)
            NSApp.activate(ignoringOtherApps: true)
        }
        ShowOnboardingButton()
        Divider()
        Button(T("Oruri Pro…")) {
            openWindow(id: "main")
            state.showPro = true
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        Button(T("Quit")) { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

/// Reabre o onboarding (para testes) — no menu Help e no menu bar.
struct ShowOnboardingButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(T("Show Onboarding…")) {
            openWindow(id: "onboarding")
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
