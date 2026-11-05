import AppKit
import SwiftUI

/// Atalho composto: teclas modificadoras juntas (⌃⇧) ou modificadoras + uma tecla (⌃⇧D).
/// Salvo nas configurações como texto: "combo|<modificadores>|<keyCode ou -1>|<nome mostrado>".
struct ComboShortcut: Equatable {
    static let relevantFlags: NSEvent.ModifierFlags = [.command, .option, .control, .shift, .function]
    /// Teclas proibidas: Esc, F1–F12, Backspace (Delete), Forward Delete, Enter/Return.
    /// Caps Lock é um interruptor no macOS: não dá para "segurar"; atalhos com ele funcionam como liga/desliga.
    static let capsLockKeyCode: UInt16 = 57
    static let forbiddenKeyCodes: Set<UInt16> = [53, 122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 51, 117, 36, 76]

    var modifiers: NSEvent.ModifierFlags
    /// nil = só modificadoras.
    var keyCode: UInt16?
    var label: String

    var encoded: String { "combo|\(modifiers.rawValue)|\(keyCode.map { Int($0) } ?? -1)|\(label)" }

    init(modifiers: NSEvent.ModifierFlags, keyCode: UInt16?, label: String) {
        self.modifiers = modifiers.intersection(Self.relevantFlags)
        self.keyCode = keyCode
        self.label = label
    }

    init?(encoded: String) {
        let parts = encoded.split(separator: "|", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 4, parts[0] == "combo", let raw = UInt(parts[1]), let code = Int(parts[2]) else { return nil }
        self.init(modifiers: NSEvent.ModifierFlags(rawValue: raw), keyCode: code < 0 ? nil : UInt16(code), label: parts[3])
    }

    /// Nome para mostrar na lista de atalhos (atalhos simples aparecem como estão).
    static func displayName(_ trigger: String) -> String {
        ComboShortcut(encoded: trigger)?.label ?? trigger
    }

    static func symbols(_ flags: NSEvent.ModifierFlags) -> String {
        var s = ""
        if flags.contains(.function) { s += "fn " }
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option) { s += "⌥" }
        if flags.contains(.shift) { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        return s
    }

    static func keyName(_ event: NSEvent) -> String {
        switch event.keyCode {
        case 49: return "Space"
        case 48: return "Tab"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default: return (event.charactersIgnoringModifiers ?? "?").uppercased()
        }
    }
}

/// Linha que grava um atalho composto: "Aperte as teclas juntas…".
struct ComboRecorderRow: View {
    let onSave: (ComboShortcut) -> Void
    let onCancel: () -> Void

    @LocalState private var monitor: Any?
    @LocalState private var peakFlags: NSEvent.ModifierFlags = []
    @LocalState private var preview = ""
    @LocalState private var message = "Press the keys together (Esc to cancel)"
    /// Caps Lock apertado na gravação: espera um instante por outras modificadoras antes de salvar.
    @LocalState private var capsPending = false
    @LocalState private var capsTimer: DispatchWorkItem?

    var body: some View {
        HStack {
            Image(systemName: "keyboard").foregroundStyle(Theme.accent)
            Text(preview.isEmpty ? T(message) : preview)
                .font(.system(size: 12, weight: preview.isEmpty ? .regular : .semibold))
                .foregroundStyle(preview.isEmpty ? Theme.secondaryText : Theme.primaryText)
            Spacer()
            Button(T("Cancel"), action: stop).buttonStyle(.link)
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.accent, lineWidth: 1.5))
        .onAppear(perform: start)
        .onDisappear { if let monitor { NSEvent.removeMonitor(monitor) } }
    }

    private func start() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            let flags = event.modifierFlags.intersection(ComboShortcut.relevantFlags)
            if event.type == .flagsChanged {
                if event.keyCode == ComboShortcut.capsLockKeyCode {
                    capsPending = true
                    peakFlags.formUnion(flags)
                    preview = ComboShortcut.symbols(peakFlags) + "⇪ Caps Lock"
                    scheduleCapsFinish()
                    return nil
                }
                if capsPending {
                    // Modificadoras junto com o Caps Lock, em qualquer ordem.
                    peakFlags.formUnion(flags)
                    preview = ComboShortcut.symbols(peakFlags) + "⇪ Caps Lock"
                    scheduleCapsFinish()
                    return nil
                }
                if flags.isEmpty {
                    // Soltou tudo: se eram 2+ modificadoras juntas, vira um atalho só de modificadoras.
                    let count = [NSEvent.ModifierFlags.command, .option, .control, .shift, .function].filter { peakFlags.contains($0) }.count
                    if count >= 2 {
                        finish(ComboShortcut(modifiers: peakFlags, keyCode: nil,
                                             label: ComboShortcut.symbols(peakFlags).trimmingCharacters(in: .whitespaces)))
                    }
                    peakFlags = []
                    preview = ""
                } else {
                    peakFlags.formUnion(flags)
                    preview = ComboShortcut.symbols(peakFlags)
                }
                return nil
            }
            // keyDown
            if event.keyCode == 53 { stop(); return nil } // Esc cancela
            if capsPending {
                message = "With Caps Lock, use only ⌃ ⌥ ⇧ ⌘ fn (no letters)"
                return nil
            }
            if ComboShortcut.forbiddenKeyCodes.contains(event.keyCode) {
                message = "That key can't be used. Try another (Esc to cancel)"
                preview = ""
                return nil
            }
            guard !flags.isEmpty else {
                message = "Hold at least one of ⌃ ⌥ ⇧ ⌘ fn with the key"
                return nil
            }
            finish(ComboShortcut(modifiers: flags, keyCode: event.keyCode,
                                 label: ComboShortcut.symbols(flags) + ComboShortcut.keyName(event)))
            return nil
        }
    }

    private func scheduleCapsFinish() {
        capsTimer?.cancel()
        let item = DispatchWorkItem { [peakFlags] in
            finish(ComboShortcut(modifiers: peakFlags, keyCode: ComboShortcut.capsLockKeyCode,
                                 label: ComboShortcut.symbols(peakFlags) + "⇪ Caps Lock"))
        }
        capsTimer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: item)
    }

    private func finish(_ combo: ComboShortcut) {
        capsTimer?.cancel()
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        onSave(combo)
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        onCancel()
    }
}
