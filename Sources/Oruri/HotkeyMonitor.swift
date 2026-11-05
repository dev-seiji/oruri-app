import AppKit

/// Observa a tecla de ditado em qualquer app.
/// - Segurar: grava enquanto a tecla estiver pressionada (Hold to record).
/// - Dois toques rápidos: trava a gravação ligada; outro toque para (Hands-free).
/// Monitores globais de teclado exigem a permissão de Acessibilidade.
final class HotkeyMonitor {
    /// Teclas simples: nome mostrado em Settings → teclas físicas (esquerda/direita).
    /// "Command" sozinho vale para os dois lados; "Left Command"/"Right Command" para um lado só.
    static let simpleKeys: [(name: String, left: UInt16?, right: UInt16?)] = [
        ("Fn", nil, nil), ("Command", 55, 54), ("Option", 58, 61), ("Control", 59, 62), ("Shift", 56, 60),
    ]

    /// Nome salvo → códigos de tecla. Inclui os nomes antigos ("Right ⌘"…) para não quebrar atalhos salvos.
    static let keyCodesByName: [String: Set<UInt16>] = {
        var map: [String: Set<UInt16>] = ["Fn": [63]]
        for key in simpleKeys {
            guard let left = key.left, let right = key.right else { continue }
            map[key.name] = [left, right]
            map["Left \(key.name)"] = [left]
            map["Right \(key.name)"] = [right]
        }
        let legacy: [String: Set<UInt16>] = ["Right ⌘": [54], "Left ⌘": [55], "Right ⌥": [61], "Left ⌥": [58],
                                              "Right ⌃": [62], "Left ⌃": [59], "Right ⇧": [60]]
        return map.merging(legacy) { current, _ in current }
    }()

    var triggers: [String] = ["Fn"]
    var holdToRecord = true
    var handsFree = true

    var onStart: () -> Void = {}
    var onStop: () -> Void = {}
    var onCancel: () -> Void = {}
    var isRecording: () -> Bool = { false }

    private var monitors: [Any] = []
    private var pressedAt: Date?
    private var lastTapAt: Date?
    private var locked = false
    /// Uma tecla pressionada junto com o gatilho (ex.: fn+F5) cancela o gesto.
    private var otherKeyDuringPress = false

    private static let tapThreshold: TimeInterval = 0.3   // abaixo disso é um "toque", não "segurar"
    private static let doubleTapWindow: TimeInterval = 0.45

    func start() {
        stop()
        let flags: NSEvent.EventTypeMask = [.flagsChanged]
        let keys: NSEvent.EventTypeMask = [.keyDown, .keyUp]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: flags, handler: { [weak self] in self?.handleFlags($0) }) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: keys, handler: { [weak self] in self?.handleKey($0) }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: flags, handler: { [weak self] in self?.handleFlags($0); return $0 }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: keys, handler: { [weak self] event in
            guard let self else { return event }
            return self.handleKey(event) ? nil : event
        }) { monitors.append(m) }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    private var triggerKeyCodes: Set<UInt16> {
        triggers.reduce(into: Set<UInt16>()) { $0.formUnion(Self.keyCodesByName[$1] ?? []) }
    }

    private func isDown(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 63: event.modifierFlags.contains(.function)
        case 54, 55: event.modifierFlags.contains(.command)
        case 58, 61: event.modifierFlags.contains(.option)
        case 59, 62: event.modifierFlags.contains(.control)
        case 56, 60: event.modifierFlags.contains(.shift)
        default: false
        }
    }

    /// Atalhos compostos salvos em `triggers` ("combo|…").
    private var combos: [ComboShortcut] { triggers.compactMap(ComboShortcut.init(encoded:)) }
    /// Atalho composto em andamento: só modificadoras, ou o keyCode da tecla segurada.
    private var activeModifierCombo = false
    private var activeComboKey: UInt16?
    /// Último toque no Caps Lock (para aceitar "Caps Lock e depois Shift").
    private var lastCapsAt: Date?

    private func toggleFromCaps() {
        lastCapsAt = nil
        if isRecording() { onStop() } else { onStart() }
    }

    private func handleFlags(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(ComboShortcut.relevantFlags)
        // Caps Lock (sozinho ou com modificadoras, em qualquer ordem): cada toque liga ou desliga a gravação.
        let capsCombos = combos.filter { $0.keyCode == ComboShortcut.capsLockKeyCode }
        if event.keyCode == ComboShortcut.capsLockKeyCode {
            lastCapsAt = Date()
            if capsCombos.contains(where: { $0.modifiers == flags }) { toggleFromCaps() }
            return
        }
        if let last = lastCapsAt, Date().timeIntervalSince(last) < 1.0,
           capsCombos.contains(where: { $0.modifiers == flags && !flags.isEmpty }) {
            toggleFromCaps()
            return
        }
        // Atalho composto só de modificadoras (ex.: ⌃⇧): começa quando todas estão juntas, termina ao soltar uma.
        if let combo = combos.first(where: { $0.keyCode == nil }) {
            if !activeModifierCombo && flags == combo.modifiers {
                activeModifierCombo = true
                pressed()
                return
            } else if activeModifierCombo && flags != combo.modifiers {
                activeModifierCombo = false
                released()
                return
            }
        }
        guard triggerKeyCodes.contains(event.keyCode) else { return }
        if isDown(event) { pressed() } else { released() }
    }

    /// Esc cancela; qualquer outra tecla durante o gesto o invalida. Devolve true se consumiu a tecla.
    @discardableResult
    private func handleKey(_ event: NSEvent) -> Bool {
        // Atalho composto com tecla (ex.: ⌃⇧D): apertar começa, soltar a tecla termina.
        if event.type == .keyUp {
            if event.keyCode == activeComboKey {
                activeComboKey = nil
                released()
                return true
            }
            return false
        }
        let flags = event.modifierFlags.intersection(ComboShortcut.relevantFlags)
        if combos.contains(where: { $0.keyCode == event.keyCode && $0.modifiers == flags }) {
            if !event.isARepeat {
                activeComboKey = event.keyCode
                pressed()
            }
            return true
        }
        if event.keyCode == 53, isRecording() { // Esc
            locked = false
            pressedAt = nil
            onCancel()
            return true
        }
        if pressedAt != nil { otherKeyDuringPress = true }
        return false
    }

    private func pressed() {
        otherKeyDuringPress = false
        pressedAt = Date()
        if locked {
            // Modo mãos-livres ligado: um toque encerra.
            locked = false
            onStop()
            pressedAt = nil
            return
        }
        if holdToRecord && !isRecording() { onStart() }
    }

    private func released() {
        guard let pressedAt else { return }
        self.pressedAt = nil
        let held = Date().timeIntervalSince(pressedAt)

        if otherKeyDuringPress {
            // Era um atalho do sistema (fn+tecla), não ditado.
            if isRecording() && !locked { onCancel() }
            return
        }

        if held < Self.tapThreshold {
            if handsFree, let last = lastTapAt, Date().timeIntervalSince(last) < Self.doubleTapWindow {
                // Segundo toque: trava a gravação ligada.
                lastTapAt = nil
                locked = true
                if !isRecording() { onStart() }
                return
            }
            lastTapAt = Date()
            // Toque curto e solto: descarta (provavelmente foi sem querer), a menos que vire duplo toque.
            if holdToRecord && isRecording() {
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.doubleTapWindow) { [weak self] in
                    guard let self, !self.locked, self.pressedAt == nil, self.isRecording() else { return }
                    self.onCancel()
                }
            }
            return
        }

        if holdToRecord && isRecording() { onStop() }
    }
}
