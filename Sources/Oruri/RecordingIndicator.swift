import SwiftUI
import AppKit
import Observation

/// Bolha de gravação minimalista: um NSPanel sem borda, acima das outras janelas, no centro da tela,
/// logo acima do Dock. Mostra só o ícone do app em que o texto vai entrar e a onda da voz;
/// sobe ao começar o ditado e desce ao terminar. Não tem botões: soltar a tecla para, Esc cancela.
@MainActor
final class RecordingIndicatorController {
    private let state: AppState
    private var panel: NSPanel?
    private var visible = false

    private static let size = NSSize(width: 360, height: 60)
    /// Quanto a bolha sobe (e desce) ao aparecer e sumir.
    private static let travel: CGFloat = 22

    init(state: AppState) {
        self.state = state
        observe()
    }

    /// Re-registra o tracking a cada mudança (withObservationTracking dispara uma vez só).
    private func observe() {
        withObservationTracking {
            _ = state.phase
            _ = state.hud
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.update()
                self?.observe()
            }
        }
    }

    private func update() {
        if state.phase != .idle || state.hud != nil { show() } else { hide() }
    }

    private func show() {
        guard !visible else { return }
        visible = true
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let target = restingOrigin()
        panel.setFrameOrigin(NSPoint(x: target.x, y: target.y - Self.travel))
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
            panel.animator().setFrameOrigin(target)
            panel.animator().alphaValue = 1
        }
    }

    private func hide() {
        guard visible, let panel else { return }
        visible = false
        let origin = panel.frame.origin
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrameOrigin(NSPoint(x: origin.x, y: origin.y - Self.travel))
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                // Se um novo ditado começou durante a descida, a bolha fica.
                guard let self, !self.visible else { return }
                self.panel?.orderOut(nil)
            }
        })
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false // a sombra é desenhada pelo SwiftUI
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true // sem botões: cliques passam para o que está atrás
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let host = NSHostingView(rootView: RecordingIndicatorView().environment(state))
        host.frame = NSRect(origin: .zero, size: Self.size)
        panel.contentView = host
        return panel
    }

    /// Centro da tela em que está o mouse, logo acima do Dock (a `visibleFrame` já exclui o Dock).
    private func restingOrigin() -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let area = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(x: area.midX - Self.size.width / 2, y: area.minY + 26)
    }
}

struct RecordingIndicatorView: View {
    @Environment(AppState.self) private var state
    private var transcribing: Bool { state.phase == .transcribing }
    private var notice: String? { state.phase == .idle ? state.hud : nil }

    var body: some View {
        content
            .frame(height: 32)
            .background(Capsule().fill(Theme.indicatorBackground))
            .overlay(Capsule().stroke(Theme.indicatorBorder))
            .shadow(color: .black.opacity(0.28), radius: 8, y: 3)
            .animation(.easeOut(duration: 0.2), value: transcribing)
            .animation(.easeOut(duration: 0.2), value: notice)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 10)
    }

    @ViewBuilder
    private var content: some View {
        if let notice {
            HStack(spacing: 7) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 11, weight: .semibold))
                Text(T(notice))
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .transition(.opacity)
        } else {
            HStack(spacing: 8) {
                Image(nsImage: state.dictationAppIcon ?? NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 20, height: 20)
                ZStack {
                    if transcribing {
                        TranscribingDots().transition(.opacity)
                    } else {
                        Waveform(level: state.audioLevel).transition(.opacity)
                    }
                }
                .frame(width: 62, height: 18)
            }
            .padding(.leading, 6)
            .padding(.trailing, 11)
            .transition(.opacity)
        }
    }
}

/// Três pontinhos piscando enquanto transcreve.
private struct TranscribingDots: View {
    /// Brilho de cada pontinho (0…1), defasado para piscarem em sequência.
    static func phase(_ t: Double, index: Int) -> Double {
        let angle: Double = t * 2 * Double.pi - Double(index) * 0.9
        return (sin(angle) + 1) / 2
    }

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    let phase: Double = Self.phase(t, index: i)
                    Circle()
                        .fill(.white)
                        .frame(width: 5, height: 5)
                        .opacity(0.3 + 0.7 * phase)
                        .scaleEffect(0.8 + 0.2 * phase)
                }
            }
        }
    }
}

/// Forma de onda animada — barras com alturas de senóides sobrepostas, escaladas pelo nível do microfone.
private struct Waveform: View {
    var level: Float
    private let bars = 14

    private func barHeight(_ t: Double, index: Int) -> CGFloat {
        let x = Double(index)
        let envelope: Double = sin(Double.pi * (x + 0.5) / Double(bars))
        let wave: Double = abs(sin(t * 6.1 + x * 0.7)) * 0.6 + abs(sin(t * 3.3 - x * 1.1)) * 0.4
        let gain: Double = 0.12 + 0.88 * Double(level)
        return CGFloat(max(3, 17 * envelope * wave * gain))
    }

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2.5) {
                ForEach(0..<bars, id: \.self) { i in
                    Capsule()
                        .fill(.white.opacity(0.92))
                        .frame(width: 2.5, height: barHeight(t, index: i))
                }
            }
        }
    }
}
