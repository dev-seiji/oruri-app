import AppKit
import ApplicationServices
import ServiceManagement

/// Coloca o texto final no app em foco.
enum Delivery {
    enum Outcome { case pasted, typed, copiedOnly }

    static var isAccessibilityTrusted: Bool { AXIsProcessTrusted() }

    /// Mostra o pedido do sistema (abre Ajustes › Acessibilidade se ainda não autorizado).
    @discardableResult
    static func requestAccessibility() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    /// Bundle ID do app em foco agora (para o modo literal em apps de IA/terminal).
    static var frontmostBundleID: String? { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }

    /// Há onde colar no app da frente? Um ⌘V sem campo de texto simplesmente não faz nada,
    /// então só deixamos de colar quando com certeza não há onde escrever.
    static var hasPasteTarget: Bool {
        guard isAccessibilityTrusted, let app = NSWorkspace.shared.frontmostApplication else { return false }
        if app.bundleIdentifier == Bundle.main.bundleIdentifier { return false }
        var focused: CFTypeRef?
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
           focused != nil { return true }
        // Apps feitos com Electron/Chromium (Claude, ChatGPT, Chrome, Slack, VS Code…) não informam o
        // elemento em foco ao macOS, mas aceitam ⌘V normalmente. Só não colamos no Finder sem campo em foco
        // (área de trabalho), onde não há onde escrever.
        return app.bundleIdentifier != "com.apple.finder"
    }

    static func deliver(_ text: String, settings: Settings, longRecording: Bool) -> Outcome {
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)

        // Gravações longas (>5 min) só vão para a área de transferência, para não despejar texto sem querer.
        if longRecording && settings.holdLongRecordings {
            copy(text)
            return .copiedOnly
        }
        guard settings.autoPaste, isAccessibilityTrusted else {
            copy(text)
            return .copiedOnly
        }
        if settings.notifyNoPasteTarget && !hasPasteTarget {
            copy(text)
            return .copiedOnly
        }

        if settings.pasteInsteadOfTyping {
            copy(text)
            sendCommandV()
            if !settings.copyToClipboard, let previous {
                // Restaura o conteúdo anterior depois que o app colou.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    pasteboard.clearContents()
                    pasteboard.setString(previous, forType: .string)
                }
            }
            return .pasted
        } else {
            type(text)
            if settings.copyToClipboard { copy(text) }
            return .typed
        }
    }

    static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private static func sendCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9
        let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    /// Digita o texto com eventos de teclado sintéticos (em blocos de até 20 caracteres).
    private static func type(_ text: String) {
        let source = CGEventSource(stateID: .combinedSessionState)
        var chunk: [UniChar] = []
        func flush() {
            guard !chunk.isEmpty else { return }
            let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            down?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
            up?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
            chunk.removeAll()
            usleep(4_000)
        }
        for unit in text.utf16 {
            chunk.append(unit)
            if chunk.count == 20 { flush() }
        }
        flush()
    }
}

/// Integrações com o sistema: som, mídia, iniciar com o Mac, hook pós-gravação.
enum SystemIntegration {
    static func playStartSound() {
        NSSound(named: "Tink")?.play()
    }

    /// Players que o Oruri sabe pausar e retomar: bundle ID → nome do app no AppleScript.
    private static let mediaPlayers = [("com.spotify.client", "Spotify"), ("com.apple.Music", "Music")]

    /// Pausa só os players que estão abertos e tocando, e devolve os nomes deles para retomar depois.
    /// Não usa a tecla Play/Pause: quando nada está tocando, ela faz o macOS abrir o Music.
    /// Roda numa fila própria: o Music pode levar segundos para responder ao AppleScript
    /// e, na thread principal, isso atrasava a bolha e a tecla de parar.
    private static let mediaQueue = DispatchQueue(label: "oruri.media")

    /// `chromeBlocked`: o Chrome recusou porque "Permitir JavaScript de Eventos da Apple" está desligado.
    static func pausePlayingMedia(completion: @escaping @MainActor (_ paused: [String], _ chromeBlocked: Bool) -> Void) {
        mediaQueue.async {
            var paused = pausePlayingMediaNow()
            var chromeBlocked = false
            if NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == chromeBundleID }) {
                switch runAppleScript(chromePauseScript) {
                case "paused": paused.append(chromeName)
                case "blocked": chromeBlocked = true
                default: break
                }
            }
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(paused, chromeBlocked) } }
        }
    }

    // MARK: Áudio no Chrome (YouTube, Spotify Web…)
    // O Chrome não tem "player state": o Oruri pausa os <video>/<audio> que estão tocando em cada aba, marca
    // esses elementos e, ao terminar, dá play só neles. Exige, uma vez, Visualizar › Desenvolvedor ›
    // Permitir JavaScript de Eventos da Apple no Chrome. shortcut: não alcança players dentro de iframes
    // (vídeo do YouTube embutido em outro site); dá para cobrir depois com a Media Session API, se fizer falta.

    private static let chromeBundleID = "com.google.Chrome"
    private static let chromeName = "Google Chrome"

    private static let chromePauseScript = """
    tell application "Google Chrome"
        set total to 0
        set blocked to false
        repeat with w in windows
            repeat with t in tabs of w
                try
                    set total to total + (execute t javascript "(()=>{let n=0;document.querySelectorAll('video,audio').forEach(m=>{if(!m.paused){m.pause();m.dataset.oruriPaused='1';n++}});return n})()")
                on error e
                    if e contains "turned off" then set blocked to true
                end try
            end repeat
        end repeat
        if total > 0 then return "paused"
        if blocked then return "blocked"
        return "idle"
    end tell
    """

    private static let chromeResumeScript = """
    tell application "Google Chrome"
        repeat with w in windows
            repeat with t in tabs of w
                try
                    execute t javascript "document.querySelectorAll('[data-oruri-paused]').forEach(m=>{delete m.dataset.oruriPaused;m.play()})"
                end try
            end repeat
        end repeat
    end tell
    """

    enum ChromeAccess: Equatable { case notRunning, allowed, blocked }

    /// Roda um AppleScript na fila de mídia, sem travar a tela.
    static func onMediaQueue<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { done in mediaQueue.async { done.resume(returning: work()) } }
    }

    /// O Chrome deixa o Oruri pausar vídeos? Só pergunta se ele já estiver aberto (o AppleScript abriria o Chrome).
    static func chromeAccess() -> ChromeAccess {
        guard NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == chromeBundleID }) else { return .notRunning }
        let script = """
        tell application "Google Chrome"
            repeat with w in windows
                repeat with t in tabs of w
                    try
                        execute t javascript "1"
                        return "allowed"
                    on error e
                        if e contains "turned off" then return "blocked"
                    end try
                end repeat
            end repeat
        end tell
        return "allowed"
        """
        return runAppleScript(script) == "blocked" ? .blocked : .allowed
    }

    /// Abre o Chrome já no menu View › Developer, com "Allow JavaScript from Apple Events" à vista: a pessoa só
    /// clica nele. O Oruri não clica sozinho porque o Chrome ignora cliques simulados nessa opção (testado em
    /// 4 nov 2026: clique, AXPress e teclado não mudam o estado), uma trava de segurança dele.
    /// shortcut: acha os menus pelos nomes em inglês, português, espanhol e japonês; em outro idioma devolve false
    /// e a tela mostra o passo a passo.
    static func showChromeJavaScriptMenu() -> Bool {
        let script = """
        tell application "Google Chrome" to activate
        delay 0.3
        tell application "System Events" to tell process "Google Chrome"
            set viewMenu to missing value
            repeat with n in {"View", "Visualizar", "Ver", "表示"}
                if viewMenu is missing value and (exists menu bar item (n as text) of menu bar 1) then set viewMenu to menu bar item (n as text) of menu bar 1
            end repeat
            if viewMenu is missing value then return "no-menu"
            click viewMenu
            delay 0.2
            repeat with n in {"Developer", "Desenvolvedor", "Desarrollador", "開発 / 管理"}
                if exists menu item (n as text) of menu 1 of viewMenu then
                    click menu item (n as text) of menu 1 of viewMenu
                    return "shown"
                end if
            end repeat
            key code 53
        end tell
        return "no-menu"
        """
        return runAppleScript(script) == "shown"
    }

    private static func pausePlayingMediaNow() -> [String] {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        var paused: [String] = []
        for (bundleID, name) in mediaPlayers where running.contains(bundleID) {
            let script = """
            tell application "\(name)"
                if player state is playing then
                    pause
                    return "paused"
                end if
            end tell
            return "idle"
            """
            if runAppleScript(script) == "paused" { paused.append(name) }
        }
        return paused
    }

    /// Retoma os players pausados por `pausePlayingMedia()`.
    static func resumeMedia(_ players: [String]) {
        mediaQueue.async {
            for name in players {
                runAppleScript(name == chromeName ? chromeResumeScript : "tell application \"\(name)\" to play")
            }
        }
    }

    @discardableResult
    private static func runAppleScript(_ source: String) -> String? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error { NSLog("Oruri: media control failed: \(error)") }
        return result?.stringValue
    }

    static func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Oruri: launch at login failed: \(error.localizedDescription)")
        }
    }

    /// Variáveis que o comando pós-gravação recebe.
    static func hookVariables(recording: Recording, timestamp: String) -> [String: String] {
        var env = [
            "ORURI_TEXT": recording.text,
            "ORURI_TIMESTAMP": timestamp,
            "ORURI_DURATION": String(format: "%.1f", recording.duration),
        ]
        if let audio = Store.audioURL(for: recording) { env["ORURI_AUDIO_PATH"] = audio.path }
        return env
    }

    /// Roda o comando do usuário via /bin/sh -c, com o texto em variáveis de ambiente e JSON no stdin.
    static func runPostHook(command: String, recording: Recording) {
        guard !command.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        let timestamp = ISO8601DateFormatter().string(from: recording.date)
        process.environment = ProcessInfo.processInfo.environment
            .merging(hookVariables(recording: recording, timestamp: timestamp)) { _, new in new }
        let stdin = Pipe()
        process.standardInput = stdin
        do {
            try process.run()
            let payload: [String: Any] = [
                "text": recording.text, "timestamp": timestamp, "duration": recording.duration,
                "audio_path": Store.audioURL(for: recording)?.path ?? NSNull(),
            ]
            if let data = try? JSONSerialization.data(withJSONObject: payload) {
                stdin.fileHandleForWriting.write(data)
            }
            try? stdin.fileHandleForWriting.close()
        } catch {
            NSLog("Oruri: post-record hook failed: \(error.localizedDescription)")
        }
    }
}
