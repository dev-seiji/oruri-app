import AVFoundation
import SwiftUI

/// Chave do AppStorage que marca o onboarding como concluído.
enum OnboardingKeys {
    static let completed = "hasCompletedOnboarding"
}

enum OnboardingStep: Int, CaseIterable {
    case permissions, dictateKey, speechModel, cleanup
}

/// Onboarding de primeiro uso em 4 passos: permissões (pedidas de verdade), tecla de ditado,
/// motor de transcrição e idioma, e limpeza por IA.
struct OnboardingView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow
    @AppStorage(OnboardingKeys.completed) private var completed = false

    @LocalState private var step: OnboardingStep = .permissions
    @LocalState private var micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @LocalState private var accessibilityGranted = Delivery.isAccessibilityTrusted

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 34)
                .padding(.bottom, 22)

            Group {
                switch step {
                case .permissions:
                    PermissionsStep(micGranted: $micGranted, accessibilityGranted: $accessibilityGranted) {
                        // "Once both are granted, setup moves on by itself."
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                            if step == .permissions { go(to: .dictateKey) }
                        }
                    }
                case .dictateKey: DictateKeyStep()
                case .speechModel: SpeechModelStep()
                case .cleanup: CleanupStep()
                }
            }
            .padding(.horizontal, 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .opacity))
            .id(step)

            footer
        }
        .frame(width: 560, height: 580)
        .background(StageBackground())
    }

    private var header: some View {
        VStack(spacing: 6) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
                .background(Circle().fill(Theme.stageRing).frame(width: 92, height: 92))
                .padding(.bottom, 10)
            Text(T("Welcome to Oruri"))
                .font(.system(size: 23, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.primaryText)
            Text(T("Dictate anywhere on your Mac — everything stays on it"))
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.divider).frame(height: 1)
            HStack {
                if step != .permissions {
                    Button(T("Back")) { go(to: OnboardingStep(rawValue: step.rawValue - 1)!) }
                        .controlSize(.large)
                }
                Spacer()
                HStack(spacing: 6) {
                    ForEach(OnboardingStep.allCases, id: \.self) { s in
                        Capsule()
                            .fill(s == step ? Theme.accent : Theme.primaryText.opacity(0.15))
                            .frame(width: s == step ? 18 : 6, height: 6)
                    }
                }
                Spacer()
                Button(T(step == .cleanup ? "Start dictating" : "Continue")) {
                    if let next = OnboardingStep(rawValue: step.rawValue + 1) { go(to: next) } else { finish() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24)
            .frame(height: 64)
            .background(Theme.card)
        }
    }

    private func go(to next: OnboardingStep) {
        withAnimation(.easeOut(duration: 0.25)) { step = next }
    }

    private func finish() {
        completed = true
        step = .permissions
        dismissWindow(id: "onboarding")
        openWindow(id: "main")
    }
}

// MARK: - Passos

private struct StepTitle: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(T(title))
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.primaryText)
            Text(T(subtitle))
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 14)
    }
}

private struct PermissionsStep: View {
    @Binding var micGranted: Bool
    @Binding var accessibilityGranted: Bool
    let onAllGranted: () -> Void
    @LocalState private var advanced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepTitle(title: "First, two permissions",
                      subtitle: "Oruri needs to hear you and type for you. Once both are granted, setup moves on by itself.")
            SettingsSection {
                permissionRow(icon: "mic.fill", title: "Microphone",
                              subtitle: "To hear your dictation.",
                              granted: $micGranted)
                Rectangle().fill(Theme.divider).frame(height: 1)
                permissionRow(icon: "accessibility", title: "Accessibility",
                              subtitle: "So the dictate key works everywhere and text lands in the app you're using.",
                              granted: $accessibilityGranted)
            }
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            accessibilityGranted = Delivery.isAccessibilityTrusted
            if micGranted && accessibilityGranted && !advanced {
                advanced = true
                onAllGranted()
            }
        }
    }

    private func permissionRow(icon: String, title: String, subtitle: String, granted: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.pillBackground))
            SettingsRow(title: title, subtitle: subtitle) {
                if granted.wrappedValue {
                    GrantedLabel()
                } else {
                    Button(T("Grant Access")) {
                        if title == "Microphone" {
                            AVCaptureDevice.requestAccess(for: .audio) { ok in
                                DispatchQueue.main.async { withAnimation { micGranted = ok } }
                            }
                        } else {
                            Delivery.requestAccessibility()
                            Delivery.openAccessibilitySettings()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                }
            }
        }
    }
}

private struct DictateKeyStep: View {
    @Environment(AppState.self) private var state

    private var usesFn: Bool { state.settings.triggers.first != "Right ⌘" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            StepTitle(title: "Choose your dictate key",
                      subtitle: "Hold it down to talk, release to insert the text.")
            ChoiceCard(isSelected: usesFn, action: { state.settings.triggers = ["Fn"] }) {
                KeyCap(text: "fn")
                Text(T("Hold fn (default)")).font(.system(size: 13, weight: .medium))
            }
            ChoiceCard(isSelected: !usesFn, action: { state.settings.triggers = ["Right ⌘"] }) {
                KeyCap(text: "right ⌘")
                Text(T("Hold Right Command")).font(.system(size: 13, weight: .medium))
            }
            Group {
                if usesFn {
                    Text(T("Emoji stays available with fn Space, and you can pick any key or combination later in Settings."))
                } else {
                    Text(T("You can pick any key or combination later in Settings."))
                }
            }
            .font(.system(size: 11.5))
            .foregroundStyle(Theme.secondaryText)
            .padding(.top, 4)
        }
    }
}

private struct SpeechModelStep: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        VStack(alignment: .leading, spacing: 10) {
            StepTitle(title: "Pick a speech model",
                      subtitle: "This is what turns your voice into text. On-device needs no key; Groq needs a free API key in Settings › Models.")
            ForEach(TranscriptionProvider.allCases) { p in
                ChoiceCard(isSelected: state.settings.engine == p.rawValue,
                           action: { state.settings.engine = p.rawValue; state.settings.activeModel = p.defaultModel }) {
                    modelLabel(p.title, p.subtitle)
                }
            }
            SettingsSection {
                PickerRow(title: "The language you'll dictate in",
                          options: Language.names,
                          selection: $state.settings.transcriptionLanguage, width: 140)
            }
            .padding(.top, 6)
        }
    }

    private func modelLabel(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(T(title)).font(.system(size: 13, weight: .semibold))
            Text(T(subtitle)).font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
        }
    }
}

private struct CleanupStep: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        VStack(alignment: .leading, spacing: 10) {
            StepTitle(title: "Punctuation & cleanup",
                      subtitle: "Optionally tidy punctuation and formatting with Groq (fast, in the cloud) or a local Ollama model. Spoken punctuation, numbers and your dictionary always work, with no AI.")
            SettingsSection {
                ToggleRow(title: "Clean up dictations with AI", isOn: $state.settings.llmCleanup)
            }
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: state.settings.llmCleanup ? "checkmark.circle.fill" : "minus.circle")
                    .foregroundStyle(state.settings.llmCleanup ? Theme.success : Theme.tertiaryText)
                Text(T(state.settings.llmCleanup
                     ? "On: dictations come out tidy. Pick Groq or Ollama in Settings › Output."
                     : "Off: dictations are inserted exactly as transcribed. You can turn this on later in Settings."))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 11.5))
            .foregroundStyle(Theme.secondaryText)
            .padding(.top, 2)
        }
    }
}

/// Card selecionável com radio à esquerda — mesmo visual do `EngineCard` de Settings.
private struct ChoiceCard<Label: View>: View {
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder var label: Label

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.tertiaryText)
                label
                Spacer()
            }
            .foregroundStyle(Theme.primaryText)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(isSelected ? Theme.accentSoft : Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(isSelected ? Theme.accent.opacity(0.6) : Theme.cardBorder))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
